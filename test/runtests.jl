using Displaz
using Test

function displaz_args(f::Function)
    old_binding = Displaz.run_displaz
    try
        arglist = []
        capture_args = (args)->push!(arglist, args)
        Displaz.eval(:(run_displaz = $capture_args))
        f()
        @test length(arglist) == 1
        return arglist[1]
    finally
        Displaz.eval(:(run_displaz = $old_binding))
    end
end

macro displaz_args(ex)
    quote
        displaz_args(()->$(esc(ex)))
    end
end

@testset "clearplot" begin
    @test @displaz_args(clearplot()) == `-script -server default -clear`
end

@testset "viewplot" begin
    @test @displaz_args(viewplot(center=[1,2,3])) ==
          `-script -server default -viewposition 1 2 3`
    @test @displaz_args(viewplot(center=[1.1,2.2,3.3])) ==
          `-script -server default -viewposition 1.1 2.2 3.3`

    @test @displaz_args(viewplot(radius=10)) ==
          `-script -server default -viewradius 10`
    @test @displaz_args(viewplot(radius=10.1)) ==
          `-script -server default -viewradius 10.1`

    @test @displaz_args(viewplot(rotation=(1,2,3))) ==
          `-script -server default -viewangles 1 2 3`
    @test @displaz_args(viewplot(rotation=[0 1 0; 1 0 0; 0 0 -1])) ==
          `-script -server default -viewrotation 0 1 0 1 0 0 0 0 -1`

    # All args together
    @test @displaz_args(viewplot(center=[1,2,3], radius=4, rotation=(5,6,7))) ==
          `-script -server default -viewposition 1 2 3 -viewradius 4 -viewangles 5 6 7`
end

@testset "annotation" begin
    @test @displaz_args(annotation([0, 1, 2], "Hello world")) == `-script -server default -annotation "Hello world" 0 1 2 -label "Hello world"`
    @test @displaz_args(annotation([0, 1, 2], "Hello world", "A label")) == `-script -server default -annotation "Hello world" 0 1 2 -label "A label"`
end

@testset "hook" begin

    # first make sure the command is OK:
    command = Displaz.hook_command("someserver",  
                                KeyEvent("c")=>Nothing, 
                                KeyEvent("p")=>CursorPosition)
    
    @test command == `$(Displaz._displaz_cmd) -server someserver -hook key:c null -hook key:p cursor`

    # prepare some fake Displaz outputs:
    lines = ["key:c null", 
             "key:p cursor 0 0 0"]
    event_stream = IOBuffer()
    foreach(l -> write(event_stream, l * "\n"), lines)
    seek(event_stream, 0)

    # prepare our received events buffer and a callback function:
    received = Vector{Any}() 
    callback(x...) = push!(received, x)

    # this should plow through our fake output lines and return:
    Displaz.handle_events(callback, event_stream)

    # see if we got what we expected:
    @test length(received) == 2
    @test received[1] == (KeyEvent("c"), nothing)
    @test received[2] == (KeyEvent("p"), CursorPosition([0.0, 0.0, 0.0]))

end
