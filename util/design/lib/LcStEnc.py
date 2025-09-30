# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""A life cycle state encoding class used to generate new life cycle encodings."""

import logging as log
from collections import OrderedDict

from Crypto.Hash import cSHAKE128
from lib.common import (check_int, ecc_encode, get_hd, hd_histogram,
                        is_valid_codeword, random_or_hexvalue, scatter_bits)
from topgen import secure_prng as sp

# Seed diversification constant for LcStEnc (this enables to use
# the same base randomization seed for different classes)
LC_SEED_DIVERSIFIER = 1939944205722120255

# State types and permissible format templates for entries
LC_STATE_TYPES = {
    'lc_state': ['0', 'A{}', 'B{}'],
    'lc_cnt': ['0', 'C{}', 'D{}'],
    'soc_dbg_state': ['0', 'E{}', 'F{}'],
    'ownership_state': ['0', 'G{}', 'H{}'],
    'auth_state': ['0', 'I{}', 'J{}']
}

# Customization string chosen for LC_CTRL's KMAC Application Interface
CSHAKE128_CUSTOM_PARAM_KMAC_APP_IF_LC_CTRL = 'LC_CTRL'


def _is_incremental_codeword(word1, word2):
    """Test whether word2 is incremental wrt. word1."""
    if len(word1) != len(word2):
        raise RuntimeError('Words are not of equal size')

    _word1 = int(word1, 2)
    _word2 = int(word2, 2)

    # This basically checks that the second word does not
    # clear any bits that are set to 1 in the first word.
    return ((_word1 & _word2) == _word1)


def _get_incremental_codewords(config: dict, base_cand_ecc: str, existing_words: list[str]) -> list:
    """Get possible incremental codewords fulfilling the constraints.

    This method may fail i.e. returning an empty list.
    """
    base_cand_data = base_cand_ecc[config['secded']['ecc_width']:]

    # We only need to spin through data bits that have not been set yet.
    # Hence, we first count how many bits are zero (and hence still
    # modifiable). Then, we enumerate all possible combinations and scatter
    # the bits of the enumerated values into the correct bit positions using
    # the scatter_bits() function.
    incr_cands = []
    free_bits = base_cand_data.count('0')
    for k in range(1, 2**free_bits):
        # Get incremental dataword by scattering the enumeration bits
        # into the zero bit positions in base_data.
        incr_cand = scatter_bits(base_cand_data,
                                 format(k, '0' + str(free_bits) + 'b'))

        # Dataword is correct by construction, but we need to check whether
        # the ECC bits are also incremental.
        incr_cand_ecc = ecc_encode(config['secded'], incr_cand)
        if not _is_incremental_codeword(base_cand_ecc, incr_cand_ecc):
            continue

        # Check whether the candidate fulfills the maximum
        # Hamming weight constraint
        pop_cnt = incr_cand_ecc.count('1')
        if not (pop_cnt <= config['max_hw']):
            continue

        # Check Hamming distance wrt. all existing words
        is_below_min_hd = map(
            lambda w: get_hd(incr_cand_ecc, w) < config['min_hd'],
            existing_words + [base_cand_ecc])
        if any(is_below_min_hd):
            continue

        # The candidate codeword meets all constraints. Return it
        # as one possibility in a list of candidates.
        incr_cands.append(incr_cand_ecc)

    return incr_cands


def _get_new_state_word_pair(config: dict, existing_words: list) -> tuple[int, int]:
    """Randomly generate a new incrementally writable word pair.

    This routine starts by invoking the RNG, then checks the
    resultant value for the necessary properties. If any checks
    fail, return to the top and draw a new random number.

    Returns:
        A tuple of the generated word pair.

        Note. the 'existing_words' list is also modified, by
        appending each word of the generated pair.
    """
    width = config['secded']['data_width']
    ecc_width = config['secded']['ecc_width']

    while 1:
        # Invoke RNG
        base = sp.getrandbits(width)

        # Apply the ECC
        base = f"{base:0{width}b}"  # Bitstring
        base_cand_ecc = ecc_encode(config['secded'], base)

        # Enforce a minimum and maximum Hamming weight
        pop_cnt = base_cand_ecc.count('1')
        if not (pop_cnt >= config['min_hw'] and
                pop_cnt <= config['max_hw']):
            # Try again
            continue

        # Check Hamming distance wrt. all existing words
        is_below_min_hd = map(
            lambda w: get_hd(base_cand_ecc, w) < config['min_hd'],
            existing_words)
        # If the candidate fails to meet the minimum Hamming distance
        # relative to existing words, go back to the top.
        if any(is_below_min_hd):
            # Try again
            continue

        # Get encoded incremental candidates.
        incr_cands_ecc = _get_incremental_codewords(
            config, base_cand_ecc, existing_words)

        # If there are no valid candidates, we just start over.
        if not incr_cands_ecc:
            # Try again
            continue

        # There are valid candidates, draw one at random.
        incr_cand_ecc = sp.choice(incr_cands_ecc)

        log.debug('word {:4d}: {}|{} -> {}|{}'.format(
            int(len(existing_words) / 2),
            base_cand_ecc[ecc_width:], base_cand_ecc[0:ecc_width],
            incr_cand_ecc[ecc_width:], incr_cand_ecc[0:ecc_width]))

        return (base_cand_ecc, incr_cand_ecc)


def _validate_words(config: dict, words: list[str]):
    """Validate generated words (base and incremental)."""
    for k, w in enumerate(words):

        # Check whether word is valid wrt. to ECC polynomial.
        if not is_valid_codeword(config['secded'], w):
            raise RuntimeError(f"Codeword {w} at index {k} is not valid")

        # Check that word fulfills the Hamming weight constraints.
        pop_cnt = w.count('1')
        if (pop_cnt < config['min_hw'] or
            pop_cnt > config['max_hw']):
            raise RuntimeError(
                f"Codeword {w} at index {k} has wrong Hamming weight")

        # Check Hamming distance wrt. to all other existing words.
        # If the constraint is larger than 0 this implies uniqueness.
        if k < len(words) - 1:
            for k2, w2 in enumerate(words[k + 1:]):
                if get_hd(w, w2) < config['min_hd']:
                    raise RuntimeError(
                        f"Hamming distance between codeword {w} at index {k} "
                        f"and codeword {w2} at index {k + 1 + k2} is too low.")


def _validate_secded(config: dict):
    """Validate SECDED configuration."""
    config['secded'].setdefault('data_width', 0)
    config['secded'].setdefault('ecc_width', 0)
    config['secded'].setdefault('ecc_matrix', [[]])
    config['secded']['data_width'] = check_int(config['secded']['data_width'])
    config['secded']['ecc_width'] = check_int(config['secded']['ecc_width'])

    total_width = config['secded']['data_width'] + config['secded']['ecc_width']

    if config['secded']['data_width'] % 8:
        raise RuntimeError('SECDED data width must be a multiple of 8')

    if config['secded']['ecc_width'] != len(config['secded']['ecc_matrix']):
        raise RuntimeError('ECC matrix does not have correct number of rows')

    log.debug('SECDED Matrix:')
    for i, l in enumerate(config['secded']['ecc_matrix']):
        log.debug('ECC Bit {} Fanin: {}'.format(i, l))
        for j, e in enumerate(l):
            e = check_int(e)
            if e < 0 or e >= total_width:
                raise RuntimeError('ECC bit position is out of bounds')
            config['secded']['ecc_matrix'][i][j] = e


def _validate_constraints(config: dict):
    """Validates Hamming weight and distance constraints"""
    config.setdefault('min_hw', 0)
    config.setdefault('max_hw', 0)
    config.setdefault('min_hd', 0)
    config['min_hw'] = check_int(config['min_hw'])
    config['max_hw'] = check_int(config['max_hw'])
    config['min_hd'] = check_int(config['min_hd'])

    total_width = config['secded']['data_width'] + config['secded']['ecc_width']

    if config['min_hw'] >= total_width or \
       config['max_hw'] > total_width or \
       config['min_hw'] >= config['max_hw']:
        raise RuntimeError('Hamming weight constraints are inconsistent.')

    if config['max_hw'] - config['min_hw'] + 1 < config['min_hd']:
        raise RuntimeError('Hamming distance constraint is inconsistent.')


def _validate_tokens(config: dict) -> None:
    """Validates the tokens in the provided lc_cfg object."""
    config.setdefault('token_size', 128)
    config['token_size'] = check_int(config['token_size'])

    # 'token_size' needs to be byte aligned
    if config['token_size'] % 8:
        raise ValueError(
            f"Size of token {config['token_size']} must be byte aligned")


def _generate_hashed_tokens(config: dict) -> None:
    """Generate hashed token items for all tokens in the config object.

    For tokens with the value of '<random>', initial unhashed values are taken
    from the RNG.

    A hardware cSHAKE128 cryptographic one-way function hashes tokens for the
    LC_CTRL before they are compared to the expected token value in OTP.
    Apply this function to generate the expected hashed tokens.

    Generated new '{name}Hashed' token items are added to the list of tokens
    in the config dict.
    """
    hashed_tokens = []
    for token in config['tokens']:
        # Generate new random values for '<random>' value tokens
        random_or_hexvalue(token, 'value', config['token_size'])

        # Initialize the hashing object using the unhashed token value as input
        num_bytes = config['token_size'] // 8
        hashobj = cSHAKE128.new(
            data=token['value'].to_bytes(num_bytes, byteorder='little'),
            custom=CSHAKE128_CUSTOM_PARAM_KMAC_APP_IF_LC_CTRL.encode('UTF-8'))
        # Generate the hashed token values by extracting the token size in bytes
        # from the hashing object.
        hashed_value = int.from_bytes(hashobj.read(num_bytes), byteorder='little')

        # Create a new "Hashed" config item and add to the config object list
        hashed_token = OrderedDict()
        hashed_token['name'] = token['name'] + 'Hashed'
        hashed_token['value'] = hashed_value

        hashed_tokens.append(hashed_token)

    config['tokens'] += hashed_tokens


def _validate_state_declarations(config: dict):
    """Validates life cycle state and counter declarations."""
    # Add a new set to store the number of words in each state type for easy recall.
    config['num_words'] = {}
    for typ in LC_STATE_TYPES.keys():
        for k, state in enumerate(config[typ].keys()):
            state_words = config[typ][state]

            # Use the first entry (the zero/blank/RAW state) to define the num_words.
            if k == 0:
                config['num_words'][typ] = len(state_words)
                log.debug(
                    f"Inferred config['num_words']['{typ}'] = {config['num_words'][typ]}")

            # Check num_words for each entry matches the first.
            if len(state_words) != config['num_words'][typ]:
                raise RuntimeError(
                    f"{typ} entry {state} has incorrect length {len(state_words)}")

            # Render the possible format templates 'LC_STATE_TYPES[typ]' to check that
            # all OTP words in the list are valid for this state type.
            for j, entry in enumerate(state_words):
                legal_values = (fmt.format(j) for fmt in LC_STATE_TYPES[typ])
                if entry not in legal_values:
                    raise RuntimeError(
                        f"Illegal entry '{entry}' found in {state} of {typ}")


def _generate_words(config: dict) -> None:
    """Generate the encoding word-pairs for all lc states.

    The desired cryptographic and uniqueness properties for all words is
    checked, in themselves and relative to each other, as the generation
    process is undertaken.

    The statistics are logged after generation.
    """

    # This dict is added to the config object to hold the generated
    # encoding words for all states.
    # When querying the LcStEnc object for encodings, this dict is queried.
    config['genwords'] = {}

    # Temporary list of all words for uniqueness tests
    existing_words = []

    # For all words in all state types, generate the word-pairs
    for typ in LC_STATE_TYPES.keys():
        config['genwords'][typ] = []
        num_words = config["num_words"][typ]
        for _ in range(num_words):
            (base, incr) = _get_new_state_word_pair(config, existing_words)
            # Add the generated words to this list for feedback into
            # uniqueness tests for futher word generation
            existing_words.append(base)
            existing_words.append(incr)
            config['genwords'][typ].append((base, incr))

    # Validate the generated words
    _validate_words(config, existing_words)

    # Calculate and store statistics
    config['stats'] = hd_histogram(existing_words)
    log.debug('')
    log.debug('Hamming distance histogram:')
    log.debug('')
    for bar in config['stats']["bars"]:
        log.debug(bar)
    log.debug('')
    log.debug(f"Minimum HD: {config['stats']['min_hd']}")
    log.debug(f"Maximum HD: {config['stats']['max_hd']}")
    log.debug(f"Minimum HW: {config['stats']['min_hw']}")
    log.debug(f"Maximum HW: {config['stats']['max_hw']}")


class LcStEnc():
    """Life cycle state encoding generator class

    The constructor expects the configuration object to be passed in.
    This is typically loaded and parsed from a .hjson file.
    The constructor validates the configuration dict.

    After construction, the method generate_random_constants() should
    be called to seed and invoke the RNG to generate all random constants.
    """

    # This holds the input config dict.
    config = {}

    def __init__(self, config: dict):
        """The constructor validates the configuration dict."""

        log.debug('')
        log.debug('Generate life cycle state')
        log.debug('')

        # Validate inputs

        if 'seed' not in config:
            raise RuntimeError('Missing seed in configuration')
        if 'secded' not in config:
            raise RuntimeError('Missing secded configuration')
        if 'tokens' not in config:
            raise RuntimeError('Missing token configuration')
        for typ in LC_STATE_TYPES.keys():
            if typ not in config:
                raise RuntimeError(f"Missing definition for '{typ}'")

        log.debug('Checking SECDED.')
        _validate_secded(config)
        log.debug('')
        log.debug('Checking Hamming weight and distance constraints.')
        _validate_constraints(config)
        log.debug('')
        log.debug('Validating unhashed tokens.')
        _validate_tokens(config)
        log.debug('')
        log.debug('Checking state declarations.')
        _validate_state_declarations(config)
        log.debug('')

        self.config = config

    def generate_random_constants(self) -> None:
        """Initialize the RNG, and use it to generate word encodings.

        LC Tokens may be specified with a '<random>' unhashed value, so also generate
        any random token values before calculating the hashed token values.
        """

        rng_seed = check_int(self.config['seed'])

        # (Re-)Initialize the RNG.
        sp.reseed(LC_SEED_DIVERSIFIER + rng_seed)
        log.debug('')
        log.debug('LcStEnc RNG Seed: {0:d}'.format(rng_seed))

        log.debug('')
        log.debug('Generate hashed tokens.')
        _generate_hashed_tokens(self.config)
        log.debug('')
        log.debug('Generate incremental word encodings.')
        _generate_words(self.config)

        log.debug('')
        log.debug('Successfully generated life cycle state encodings.')
        log.debug('')

    def encode(self, typ: str, state: str):
        """Look up a state encoding and return as integer value."""

        # Validate
        if typ not in LC_STATE_TYPES:
            raise RuntimeError(f"Unknown state type '{typ}'")
        if state not in self.config[typ]:
            raise RuntimeError(f"Unknown state '{state}' of type '{typ}'")

        data_width = self.config['secded']['data_width']
        ecc_width = self.config['secded']['ecc_width']

        # Assemble list of words for this state
        words = []
        for j, entry in enumerate(self.config[typ][state]):
            # This creates an index lookup table
            val_idx = {
                fmt.format(j): i
                for i, fmt in enumerate(LC_STATE_TYPES[typ])
            }
            idx = val_idx[entry]
            if idx == 0:
                words.append(0)
            else:
                # Only extract data portion, discard ECC portion
                word = self.config['genwords'][typ][j][idx - 1][ecc_width:]
                words.append(int(word, 2))

        # Convert words to one value
        outval = 0
        for k, word in enumerate(words):
            outval += word << (data_width * k)

        return outval
