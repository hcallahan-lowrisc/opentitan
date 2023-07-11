load("@rules_sh//sh:sh.bzl", "ShBinariesInfo")

def _custom_rule_impl(ctx):
    tools = ctx.attr.tools[ShBinariesInfo]
    (tools_inputs, tools_manifest) = ctx.resolve_tools(tools = [ctx.attr.tools])


    dirname = "build-site{}".format(ctx.label.name)
    out_dir = ctx.actions.declare_directory(dirname)
    outputs = [out_dir]

    ctx.actions.run(
        outputs = outputs,
        executable = ctx.attr.build_docs,
        env = { "PATH" : ":".join(tools.paths.to_list()) },
        tools = [
            tools.executables["doxygen"],
            # tools.executables["mdbook"],
            tools.executables["hugo"],
        ],
        inputs = depset(direct = [dep[f] for f in ctx.attr.srcs] ,
                        transitive = [ tools_inputs ]),
        input_manifests = tools_manifest,
    )

custom_rule = rule(
    _custom_rule_impl,
    attrs = {
        "tools": attr.label(cfg = "exec"),
        "srcs": attr.label_list(allow_files = True, doc = "Source files"),
        "build_docs": attr.label(
            executable = True,
            cfg = "exec",
        ),

    },
)
