"""
Buffer one can easily insert/remove line segments from.
This is great for working with line data that is changing a lot with minimal
performanc impact. It's also great for batching draw calls, since you can
insert lines in different points of the program, and then draw it with a single
opengl draw call.
"""
struct LinesegmentBuffer{N}
    positions::GPUVector{Point{N, Float32}}
    colors::GPUVector{RGBAf0}
    thickness::GPUVector{Float32}
    robj::RenderObject
    range::Signal{Int}
end

function LinesegmentBuffer(pos::Point{N, <: AbstractFloat} = Point3f0(0)) where N
    positions = gpuvec(Point{N, Float32}[])
    colors = gpuvec(RGBAf0[])
    thickness = gpuvec(Float32[])
    range = Signal(0)
    robj = visualize(
        positions.buffer, :linesegment,
        color = colors.buffer,
        thickness = thickness.buffer,
        indices = range
    )
    LinesegmentBuffer{N}(
        positions,
        colors,
        thickness,
        robj.children[],
        range
    )
end

same_length_array(array, value) = fill(value, length(array))
same_length_array(arr, value::Vector) = value

function Base.append!(lsb::LinesegmentBuffer{N}, pos::Vector{Point{N, Float32}}, color, thickness) where N
    append!(lsb.positions, pos)
    append!(lsb.colors, same_length_array(pos, to_color(color)))
    append!(lsb.thickness, Float32.(same_length_array(pos, thickness)))
    push!(lsb.range, length(lsb.positions))
    return
end
function Base.empty!(lsb::LinesegmentBuffer)
    resize!(lsb.positions, 0)
    resize!(lsb.colors, 0)
    resize!(lsb.thickness, 0)
    push!(lsb.range, 0)
    return
end

to_linestyle(ls::Void) = nothing
to_linestyle(ls::AbstractVector{<:AbstractFloat}) = ls
to_linestyle(ls::Symbol) = ls

to_pattern(::Node{Void}, linewidth) = nothing
to_pattern(A::AbstractVector, linewidth) = A
function to_pattern(ls::Node{Symbol}, linewidth)
    lift_node(ls, lw) do ls, lw
        points = if ls == :dash
            [0.0, lw, 2lw, 3lw, 4lw]
        elseif ls == :dot
            tick, gap = lw/2, lw/4
            [0.0, tick, tick+gap, 2tick+gap, 2tick+2gap]
        elseif ls == :dashdot
            dtick, dgap = lw, lw
            ptick, pgap = lw/2, lw/4
            [0.0, dtick, dtick+dgap, dtick+dgap+ptick, dtick+dgap+ptick+pgap]
        elseif ls == :dashdotdot
            dtick, dgap = lw, lw
            ptick, pgap = lw/2, lw/4
            [0.0, dtick, dtick+dgap, dtick+dgap+ptick, dtick+dgap+ptick+pgap, dtick+dgap+ptick+pgap+ptick,  dtick+dgap+ptick+pgap+ptick+pgap]
        else
            error("Unkown line style: $linestyle. Available: :dash, :dot, :dashdot, :dashdotdot or a sequence of numbers enumerating the next transparent/opaque region")
        end
        points
    end
end

function lines_2glvisualize(kw_args)
    result = Dict{Symbol, Any}()
    for (k, v) in kw_args
        k in (:linestyle, :x, :y, :z, :positions) && continue
        if k == :colornorm
            k = :color_norm
        end
        if k == :colormap
            k = :color_map
        end
        if k == :positions
            k = :vertex
        end
        result[k] = to_signal(v)
    end
    result[:visible] = true
    result[:fxaa] = true
    result[:model] = eye(Mat4f0)
    result
end


@default function lines(scene, kw_args)
    xor(
        begin
            positions = to_positions(positions)
        end,
        if (x, y, z)
            x = to_array(x)
            y = to_array(y)
            z = to_array(z)
            positions = to_positions((x, y, z))
        end,
        if (x, y)
            x = to_array(x)
            y = to_array(y)
            positions = to_positions((x, y))
        end
    )
    xor(
        begin
            color = to_color(color)
        end,
        begin
            colormap = to_colormap(colormap)
            intensity = to_intensity(intensity)
            colornorm = to_colornorm(colornorm, intensity)
        end
    )
    linewidth = linewidth::Float32
    linestyle = to_linestyle(linestyle)
    pattern = to_pattern(linestyle, linewidth)
end


function _lines(style, attributes)
    scene = get_global_scene()
    attributes = lines_defaults(scene, attributes)
    data = lines_2glvisualize(attributes)
    viz = GLVisualize._default(to_signal(attributes[:positions]), Style(style), data)
    viz = GLVisualize.assemble_shader(viz).children[]
    insert_scene!(scene, style, viz, attributes)
end


for arg in ((:x, :y), (:x, :y, :z), (:positions,))
    insert_expr = map(arg) do elem
        :(attributes[$(QuoteNode(elem))] = $elem)
    end
    @eval begin
        function lines($(arg...); kw_args...)
            attributes = expand_kwargs(kw_args)
            $(insert_expr...)
            _lines(:lines, attributes)
        end
        function linesegment($(arg...); kw_args...)
            attributes = expand_kwargs(kw_args)
            $(insert_expr...)
            _lines(:linesegment, attributes)
        end
    end
end
