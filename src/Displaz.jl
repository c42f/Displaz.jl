module Displaz
using StaticArrays
using Colors

export plot3d, plot3d!, plotimage, plotimage!, clearplot, viewplot
export KeyEvent, CursorPosition, event_loop

"""
    set_displaz_cmd(cmd)

Set name or full path for where the displaz binary will be found to `cmd`.
Defaults to the environment variable `DISPLAZ_CMD`, or the string `"displaz"`
if that variable is not found.
"""
set_displaz_cmd(cmd) = global _displaz_cmd = cmd

function __init__()
    set_displaz_cmd(get(ENV, "DISPLAZ_CMD", "displaz"))
end

# Convert julia array into a type name and type appropriate for putting in the
# ply header
ply_type_convert(a::AbstractArray{UInt8})    = ("uint8",   a)
ply_type_convert(a::AbstractArray{UInt16})   = ("uint16",  a)
ply_type_convert(a::AbstractArray{UInt32})   = ("uint32",  a)
ply_type_convert(a::AbstractArray{Int8})     = ("int8",    a)
ply_type_convert(a::AbstractArray{Int16})    = ("int16",   a)
ply_type_convert(a::AbstractArray{Int32})    = ("int32",   a)
ply_type_convert(a::AbstractArray{Float32})  = ("float32", a)
ply_type_convert(a::AbstractArray{Float64})  = ("float64", a)
# Generic cases - actually do a conversion
ply_type_convert(a::AbstractArray{T}) where T <: Unsigned = ("uint32",  map(UInt32,a))
ply_type_convert(a::AbstractArray{T}) where T <: Integer = ("int32",   map(Int32,a))
ply_type_convert(a::AbstractArray{T}) where T <: Real = ("float64", map(Float64,a))


const array_semantic = 0
const vector_semantic = 1
const color_semantic = 2

# get ply header property name for given field index and semantic
function ply_property_name(semantic, idx)
    if semantic == array_semantic
        string(idx-1)
    elseif semantic == vector_semantic
        ("x", "y", "z", "w")[idx]
    elseif semantic == color_semantic
        ("r", "g", "b")[idx]
    end
end

# Write a set of points to displaz-native ply format
function write_ply_points(filename, nvertices, fields)
    converted_fields = [ply_type_convert(value) for (_,__,value) in fields]
    open(filename, "w") do fid
        write(fid, "ply\n")
        write(fid, "format binary_little_endian 1.0\n")
        write(fid, "comment Displaz native\n")
        for ((name,semantic,_), (typename, value)) in zip(fields, converted_fields)
            n = size(value,2)
            @assert(n == nvertices || n == 1)
            write(fid, "element vertex_$name $n\n")
            for i = 1:size(value,1)
                propname = ply_property_name(semantic, i)
                write(fid, "property $typename $propname\n")
            end
        end
        write(fid, "end_header\n")
        for (_,value) in converted_fields
            write(fid, value)
        end
    end
end

function write_ply_lines(filename, position, color, linebreak)
    nvalidvertices = size(position,2)

    # Create and write to ply file
    fid = open(filename, "w")
    write(fid,
        """
        ply
        format binary_little_endian 1.0
        element vertex $nvalidvertices
        property double x
        property double y
        property double z
        element color $nvalidvertices
        property float r
        property float g
        property float b
        element edge $(length(linebreak))
        property list int int vertex_index
        end_header
        """
    )

    write(fid,convert(Array{Float64,2},position))
    write(fid,color)

    realstart = 0
    linelen = []
    range = []
    for i = 1:size(linebreak,1)
        if i != size(linebreak,1)
            linelen = linebreak[i+1] - linebreak[i]
            range = realstart:realstart + linelen-1
        else
            linelen = size(position,2) - linebreak[i] + 1
            range = realstart:realstart + linelen - 1
        end
        write(fid,Int32(linelen))
        write(fid,UnitRange{Int32}(range))
        realstart = realstart + linelen
    end
    close(fid)
end

#const standard_elements = [:position  => (vector_semantic,3),
#                           :color     => (color_semantic,3),
#                           :marksize  => (array_semantic,1),
#                           :markshape => (array_semantic,1)]

const _color_names = Dict('r' => [1.0, 0,   0],
                          'g' => [0.0, 0.8, 0],
                          'b' => [0.0, 0,   0.8],
                          'c' => [0.0, 1,   1],
                          'm' => [1.0, 0,   1],
                          'y' => [1.0, 1,   0],
                          'k' => [0.0, 0,   0],
                          'w' => [1.0, 1,   1])

const _shape_ids = Dict('.' => 0,
                        's' => 1,
                        'o' => 2,
                        'x' => 3,
                        '+' => 4)

interpret_color(color) = color
interpret_color(s::AbstractString) = length(s) == 1 ? interpret_color(s[1]) : error("Unknown color abbreviation $s")
interpret_color(c::Char) = _color_names[c]
interpret_color(c::AbstractRGB) = [red(c), green(c), blue(c)]
interpret_color(c::Color) = interpret_color(RGB(c))
function interpret_color(cs::AbstractVector{T}) where T <: Color
    a = zeros(eltype(T), (3,length(cs)))
    for i=1:length(cs)
        c = RGB(cs[i])
        a[1,i] = red(c)
        a[2,i] = green(c)
        a[3,i] = blue(c)
    end
    a
end

interpret_shape(markershape) = markershape
interpret_shape(c::Char) = [_shape_ids[c]]
interpret_shape(s::Vector{Char}) = Int[_shape_ids[c] for c in s]
interpret_shape(s::AbstractString) = Int[_shape_ids[c] for c in s]

interpret_linebreak(nvertices, linebreak) = linebreak
interpret_linebreak(nvertices, i::Integer) = i == 1 ? [1] : 1:i:nvertices

interpret_position(pos::AbstractMatrix) = pos
function interpret_position(pos::AbstractVector{V}) where V <: StaticVector
    size(eltype(pos)) == (3,) || error("position should be a 3-vector")
    T = eltype(V)
    isbitstype(T) || error("Can't reinterpret position with elements $T")
    nvertices = length(pos)
    return reshape(reinterpret(T, pos), (3, nvertices))
end

function interpret_position(pos::AbstractVector{T}) where T <: Real
    size(pos) == (3,) || error("position should be a 3-vector")
    return pos
end

# Multiple figure window support
# TODO: Consider how the API below relates to Plots.jl and its tendency to
# create a lot of new figure windows rather than clearing existing ones.
mutable struct DisplazWindow
    name::AbstractString
end

_current_figure = DisplazWindow("default")
"Get handle to current figure window"
function current()
    _current_figure
end

"Get figure window by name may be new or already existing"
function figure(name::AbstractString)
    global _current_figure
    _current_figure = DisplazWindow(name)
end
"Get figure window with given id"
figure(id::Integer) = figure("Figure $id")

_figure_id = 1
"Create next incrementally named figure window, counting automatically from \"Figure 1\""
function newfigure()
    global _figure_id
    id = _figure_id
    _figure_id += 1
    figure(id)
end


"""
Add 3D points or lines to the current plot.

```
  plot3d([plotobj,] position; attr1=value1, ...)
```

The `position` array should be a set of N vertex positions, specified as 3xN
array or a `Vector` of `FixedVector{3}`.  The `plotobj` argument is optional
and determines which plot window to send the data to.  If it's not used the
data will be sent to the plot window returned by `current()`.

TODO: Revisit the nasty decision of the shape of position again - the above
choice is somewhat inconsistent with supplying markersize / markershape as a
column vector :-(  Can we have a set of consistent broadcasting rules for this?
It seems like the case of a 3x3 matrix will always be ambiguous if we try
to guess what the user wants.

### Data set attributes

The following attributes can be attached to a dataset on each call to `plot3d`:

  * `label` - A string labeling the data set

### Vertex attributes

Each point may have a set of vertex attributes attached to control the visual
representation and tag the point for inspection. You can pass any `Vector` of
`Float32` values for any custom information you like, but the following are
supported by the default shader:

  * `color`       - A color or vector of colors for each point; see below for
                    ways to specify these.
  * `intensity`   - A vector of the intensity of each point (between 0 and 1)
  * `markersize`  - Vertex marker size
  * `markershape` - Vector of vertex marker shapes.  Shape can be represented
                    either by a Char or a numeric identifier between 0 and 4:

```
                    sphere - '.' 0    square - 's' 1
                    circle - 'o' 2    times  - 'x' 3
                    cross  - '+' 4
```

#### Specifying colors

Colors may be provided in any of three ways:

* As instances of types from the ColorTypes package, for example, HSV(180,1,1).
  These are converted to RGB using the RGB constructor.
* As a `Vector` of three elements, red, green and blue, between 0.0 and 1.0.
* Using a matlab-like single color letter name string or `Char`.  Supported are
  red, green, blue, cyan, magenta, yellow, black and white; all are abbreviated
  with the first letter of the color name except black for which 'k' is used.

A color per point may be supplied as a `Vector` of `Color` subtypes or a 3xN
matrix with red, green and blue in the rows.


### Plotting points

To plot 10000 random points with distance from the origin determining the
color, and random marker shapes:
```
  P = randn(3,10000)
  c = 0.5./sumabs2(P,1) .* [1,0,0]
  plot3d(P, color=c, markershape=rand(1:4,10000))
```


### Plotting lines

To plot a piecewise linear curve between 10000 random vertices
```
  plot3d(randn(3,10000), markershape="-")
```

When plotting lines, the `linebreak` keyword argument can be used to break the
position array into multiple line segments.  Each index in the line break array
is the initial index of a line segment.
"""
function plot3d(plotobj::DisplazWindow, position; color=[1,1,1], markersize=[0.1], markershape=[0],
                label=nothing, linebreak=[1], _overwrite_label=false, shader="generic_points.glsl", kwargs...)
    position = interpret_position(position)
    nvertices = size(position, 2)
    color = interpret_color(color)
    linebreak = interpret_linebreak(nvertices, linebreak)
    size(position, 1) == 3 || error("position must be a 3xN array")
    size(color, 1)    == 3 || error("color must be a 3xN array")
    # FIXME in displaz itself.  No repeat waste should be required.
    if size(color,2) == 1
        color = repeat(color, 1, nvertices)
    end

    # works for vectors only at this stage...
    extra_fields = ((x -> (size(x[2]) == (nvertices,) || error("extra fields must be vectors of same length as number of points in position array") ;
        (x[1], array_semantic, transpose(Float32.(x[2])))) for x = pairs(kwargs)))

    # Ensure all fields are floats for now, to avoid surprising scaling in the
    # shader
    color = map(Float32,color)
    markersize = map(Float32,markersize)
    size(color,2) == nvertices || error("color must have same number of rows as position array")
    filename = tempname()*".ply"
    seriestype = "Points"
    if markershape == "-" || markershape == '-'
        # Plot lines
        # FIXME: The way this is detected is a bit of a mess - lines vs points
        # should be plotted using separate functions.
        seriestype = "Line"
        write_ply_lines(filename, position, color, linebreak)
    else # Plot points
        if length(markersize) == 1
            markersize = repeat(markersize, 1, nvertices)
        end
        markershape = interpret_shape(markershape)
        if length(markershape) == 1
            markershape = repeat(markershape, 1, nvertices)
        end
        write_ply_points(filename, nvertices, (
                         (:position, vector_semantic, position),
                         (:color, color_semantic, color),
                         # FIXME: shape of markersize??
                         (:markersize, array_semantic, vec(markersize)'),
                         (:markershape, array_semantic, vec(markershape)'),
                         extra_fields...
                         ))
    end
    if label === nothing
        label = "$seriestype [$nvertices vertices]"
    end
    addopt = _overwrite_label ? [] : "-add"
    run(`$_displaz_cmd -script $addopt -server $(plotobj.name) -label $label -shader $shader -rmtemp $filename`)
    nothing
end


"""
    mutate!([plotobj,] label, index; attr1=value1, ...))

Mutate the data in an existing displaz data set `label`, for instance to change the
position or other attribute of a subset of points (with the advantage of
reducing the amount of communication between Julia and displaz, and therefore
increasing speed).

`index` is vector of indices with reference to the original plot. The attribute
`label` is used to match with the correct data set within displaz. The
`position` attribute controls the vertex positions, and the remainder match
the original plotting command.
"""
function mutate!(label::AbstractString, index::AbstractVector{I}; kwargs...) where I <: Integer
    plotobj = _current_figure
    mutate!(plotobj, label, index; kwargs...)
end

function mutate!(plotobj::DisplazWindow, label::AbstractString, index::AbstractVector{I}; kwargs...) where I <: Integer
    nvertices = length(index)

    fields = Vector{Any}()

    push!(fields, (:index, array_semantic, map(UInt32, (index.-1)'))) # It turns out the -1 is rather important (0-based indexing)... :)

    for (fieldname, fielddata) ∈ kwargs
        if fieldname == :position
            fielddaata = interpret_position(fielddata)
            size(fielddata) == (3,nvertices) || error("position must be a 3x$nvertices array")

            push!(fields, (:position, vector_semantic, fielddata))
        elseif fieldname == :color
            fielddata = interpret_color(fielddata)
            size(fielddata, 1) == 3 || error("color must be a 3xN array")
            if size(fielddata,2) == 1
                fielddata = repeat(fielddata, 1, nvertices)
            end
            size(fielddata) == (3,nvertices,) || error("wrong number of color points")
            fielddata = map(Float32, fielddata)

            push!(fields, (:color, color_semantic, fielddata))
        elseif fieldname == :markershape
            if length(fielddata) == 1
                fielddata = repeat(fielddata, 1, nvertices)
            end
            size(fielddata) == (nvertices,) || error("wrong number of markershape points")
            fielddata = interpret_shape(fielddata)

            push!(fields, (:markershape, array_semantic, vec(fielddata)'))
        elseif fieldname == :linebreak
            if length(fielddata) == 1
                fielddata = repeat(fielddata, 1, nvertices)
            end
            fielddata = interpret_linebreak(fielddata)

            push!(fields, (:linebreak, array_semantic, vec(fielddata)'))
        else
            if length(fielddata) == 1
                fielddata = repeat(fielddata, nvertices)
            end
            size(fielddata) == (nvertices,) || error("extra fields must be vectors of same length as index array")
            fielddata = map(Float32, fielddata)

            push!(fields, (fieldname, array_semantic, vec(fielddata)'))
        end
    end

    filename = tempname()*".ply"

    write_ply_points(filename, nvertices, fields)
    run(`$_displaz_cmd -script -modify -server $(plotobj.name) -label $label -shader generic_points.glsl $filename`)
    nothing

end


"""
Overwrite points or lines with the same label on the 3D plot

See plot3d for documentation
"""
function plot3d!(plotobj::DisplazWindow, position; kwargs...)
    plot3d(plotobj, position; _overwrite_label=true, kwargs...)
end


# Plot to current window
plot3d!(position; kwargs...) = plot3d!(current(), position; kwargs...)
plot3d(position; kwargs...)  = plot3d(current(), position; kwargs...)


#-------------------------------------------------------------------------------
"""
    clearplot([plotobj::DisplazWindow=current()], [pattern1, ...])

Clear all or a subset of datasets in a plot window.

If not specified, `plotobj` is the current plot window.  If no patterns are
supplied, clears all data sets.  If one or more patterns are given, the dataset
labels matching those patterns will be removed.  Patterns shoudl be specified
using unix shell glob pattern syntax.
"""
function clearplot(plotobj::DisplazWindow, patterns...)
    unload_args = isempty(patterns) ? ["-clear"] : ["-unload", patterns...]
    run(`$_displaz_cmd -script -server $(plotobj.name) $unload_args`)
    nothing
end
clearplot(patterns...) = clearplot(current(), patterns...)



#-------------------------------------------------------------------------------
# Texture file

# Write image name (including absolute path) and vertices of the four corner to ply file
function write_ply_texture(texturefile::String, filename::String, vertices::AbstractArray)

    open(filename, "w") do f
        write(f,
            """
            ply
            format ascii 1.0
            comment TextureFile $texturefile
            element vertex 4
            property double x
            property double y
            property double z
            property double u
            property double v
            element face 1
            property list int int vertex_index
            end_header
            $(vertices[1,1]) $(vertices[1,2]) $(vertices[1,3]) 0 1
            $(vertices[2,1]) $(vertices[2,2]) $(vertices[2,3]) 1 1
            $(vertices[3,1]) $(vertices[3,2]) $(vertices[3,3]) 1 0
            $(vertices[4,1]) $(vertices[4,2]) $(vertices[4,3]) 0 0
            4 0 1 2 3
            """
        )
    end
    nothing
end


"""
Add images to the current plot.

```
  plotimage([plotobj,] texturefile, vertices; label=nothing, _overwrite_label=false)
```

The `texturefile` string should include the path (relative or absolute) to the
image to be loaded (if not in the current folder).
The `vertices` array should be a set of vertex positions specifying the corners
of the image to plot. The order is anticlockwise starting from bottom left (i.e.
(0,1), (1,1), (1,0), (0,0) in texture coordinates), and the vertices
should be specified as a 3x4 array.
The `plotobj` argument is optional and determines which plot window
to send the data to.  If it's not used the data will be sent to the plot window
returned by `current()`.
"""
function plotimage(plotobj::DisplazWindow, texturefile::String, vertices::AbstractArray; label=nothing, _overwrite_label=false)

    filename = tempname()*".ply"

    write_ply_texture(abspath(texturefile), filename, vertices)

    if label === nothing
        label = "$texturefile"
    end
    addopt = _overwrite_label ? [] : "-add"
    run(`$_displaz_cmd -script $addopt -server $(plotobj.name) -label $label -rmtemp $filename`)
    nothing
end


"""
Overwrite images with the same label

See plotimage for documentation
"""
function plotimage!(plotobj::DisplazWindow, texturefile::String, vertices::AbstractArray; kwargs...)
    plotimage(plotobj, texturefile, vertices; _overwrite_label=true, kwargs...)
end

# Plot to current window
plotimage!(texturefile, vertices; kwargs...) = plotimage!(current(), texturefile, vertices; kwargs...)
plotimage(texturefile, vertices; kwargs...)  = plotimage(current(), texturefile, vertices; kwargs...)




#-------------------------------------------------------------------------------
# 3D camera control
"""
    viewplot([plotobj::DisplazWindow=current()], label)

Set the point of view of the 3D camera.  The camera model is designed to view
an object at a given `center` of rotation, with rotations pivoting around that
position.

If not specified, `plotobj` is the current plot window.  Keyword arguments
define the camera view as follows:

* The `center` argument may be a 3D point or the label of a data set.
  If a label is supplied the centroid of the associated dataset will be used.
* The `radius` argument should be a number giving the distance that the
  camera will be away from the center of rotation.
* The `rotation` argument specifies the angles at which the camera will view
  the scene.  This should be a matrix transforming points into the standard
  OpenGL camera coordinates (+x right, +y up, -z into the scene).

"""
function viewplot(plotobj::DisplazWindow;
                  center=nothing, radius=nothing, rotation=nothing)
    center_args   = viewplot_center_args(center)
    radius_args   = viewplot_radius_args(radius)
    rotation_args = viewplot_rotation_args(rotation)
    run(`$_displaz_cmd -script -server $(plotobj.name) $center_args $radius_args $rotation_args`)
    nothing
end
viewplot(; kwargs...) = viewplot(current(); kwargs...)

# viewplot() helper stuff
# center
viewplot_center_args(::Nothing) = []
viewplot_center_args(s::AbstractString) = ["-viewlabel", string(s)]
viewplot_center_args(pos) = ["-viewposition", string(pos[1]), string(pos[2]), string(pos[3])]
# rotation
viewplot_rotation_args(::Nothing) = []
viewplot_rotation_args(M) = vcat("-viewrotation", map(string, vec(Matrix(M)'))) # Generate row-major order
# radius
viewplot_radius_args(::Nothing) = []
viewplot_radius_args(r) = ["-viewradius", string(r)]


#-------------------------------------------------------------------------------
# Event loop

include("events.jl")

end
