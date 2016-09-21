using Compat


function displaz_version()
    displaz_cmd = get(ENV, "DISPLAZ_CMD", "displaz")
    try
        verstring = readstring(`$displaz_cmd -version`)
        m = match(r"version *(.*)-g.*", verstring)
        VersionNumber(m[1])
    catch err
        warn(err)
        nothing
    end
end

ver = displaz_version()

if ver === nothing
    warn(
        """
        displaz could not be found - please check that you have it installed
        (for now, you will need to build it from source - see
        https://github.com/c42f/displaz).  To ensure julia can find it, you
        should add its location to your PATH, or optionally set the DISPLAZ_CMD
        environment variable to the full path of the executable.
        """
    )
elseif ver < v"0.3.1-317"
    warn(
        """
        You have an older version ($ver) of displaz.  You should upgrade
        to the latest version to ensure the Displaz.jl bindings work correctly.
        """
    )
end

