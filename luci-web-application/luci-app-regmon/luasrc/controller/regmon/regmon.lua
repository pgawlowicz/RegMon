module("luci.controller.regmon.regmon", package.seeall)

require ("lfs")

-- Routing and menu index for the luci dispatcher.
function index()

    -- entry for menu node
    entry({"admin", "statistics", "regmon"}, firstchild(), "Regmon", 60).dependent=false
    
    -- entry and route for the config page
    entry({"admin", "statistics", "regmon", "regmon_cbi"}, cbi("regmon/regmon_cbi"), "Config", 1)
    
    -- entry and route for the graph page
    entry({"admin", "statistics", "regmon", "graph"}, template("regmon/graph"), "Graph", 2)  

    -- route of the image
    local vars = luci.http.formvalue(nil, true)
	local span = vars.timespan or nil
	entry({"admin", "statistics", "regmon", "graph" }, 
        call("regmon_render"), "Graph", 3).query = { timespan = span }
end


-- Returns a rrd DEF declaration for a metric
function rrd_metric_def ( metric, rrd_path, file_prefix, rrd_suffix, column_name )
    local cmd = " \"DEF:" .. metric .. "=" 
              .. rrd_path .. "/" .. file_prefix .. "-" .. metric .. rrd_suffix
              .. ":" .. column_name ..":AVERAGE\" \\\n"
    return cmd
end


-- Returns a legend declaration for a metric
function rrd_metric_legend ( metric ) 
    local var = "rel_" .. metric
    return " \"GPRINT:" .. var .. ":MIN:\t\tMin\\: %8.2lf %s\" \\\n"
             .. " \"GPRINT:" .. var .. ":AVERAGE:\tAvg\\: %8.2lf %s\" \\\n"
             .. " \"GPRINT:" .. var .. ":MAX:\tMax\\: %8.2lf %s\\n\" \\\n"
end


-- Returns rrd command line parts for a metric.
--
-- metric: name of the metric
-- rrd_path: path to rrd databases
-- file_prefix: prefix of the rrd file (mostly the type, i.e. gauge, derive)
-- rrd_suffic: rrd database file extension with a leading dot
-- column_name: name of the rrd column
-- stacked: whether the shape should be declared stacked
-- color: main color of the shape
function rrd_metric_defs ( metric, rrd_path, file_prefix, rrd_suffix, column_name )

    -- declare metric
    local cmd = rrd_metric_def ( metric, rrd_path, file_prefix, rrd_suffix, column_name)

--    -- absolute values, use with 'GAUGE' rrd
--    cmd = cmd .. " \"CDEF:rel_" .. metric .. "=" .. "abs_count" .. "," .. metric .. ",/\" \\\n"

--    -- percentage output, use with 'DERIVE' rrd
    cmd = cmd .. " \"CDEF:rel_" .. metric .. "=" .. metric .. ",100,*,abs_count,/\" \\\n"

    return cmd
end


function rrd_metric_shape ( metric, stacked, shape, color )
    local var = "rel_" .. metric
    local cmd = " " .. shape .. ":"
        .. var
        .. color .. ":" .. metric .. " \\\n"
    return cmd
end


-- Creates rrd shell command and executes it.
--
-- image: path of the resulting image file
-- span: timespan as 1hour, 1day, ...
-- width: resulting image width
-- height: resulting image height
-- rrd_path: path to rrd databases
-- metrics: names of all metrics. rrd files should match
--          pattern "gauge-[metric].rrd" or derive-[metric].rrd like collectd does.
-- shape: shape of the graph (LINE2 or AREA)
-- stacked: whether the shapes should be declared stacked
function generate_rrdimage ( image, span, width, height, rrd_path,
                             metrics, shape, stacked, busy_metric ) 

    local rrd_suffix = ".rrd"
    local column_name = "value"
--    local file_prefix = "gauge"
    local file_prefix = "derive"

    local cmd = "rrdtool graph "
    cmd = cmd .. image 

    cmd = cmd .. " --end now" .. " --start end-" .. luci.util.parse_units( span ) .. "s"
    cmd = cmd .. " --upper-limit 102 --lower-limit 0 --rigid"
    cmd = cmd .. " --width " .. width
    cmd = cmd .. " --height " .. height .. " \\\n"

    local colors = { "#FF5555", "#55FF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFF55" }
    local colors2 = { "#AA0000", "#00AA00", "#0000AA", "#AA00AA", "#00AAAA", "#AAAA00" }

    -- fixme: redeclaration of "abs_count" metric name (first in /usr/bin/regmon-genconfig)
    cmd = cmd .. rrd_metric_def ( "abs_count", rrd_path, file_prefix, rrd_suffix, column_name )

    -- print defs for each metric
    for i, metric in ipairs ( metrics ) do
        cmd = cmd .. rrd_metric_defs ( metric, rrd_path, file_prefix, rrd_suffix, column_name )
    end

    cmd = cmd .. " \"CDEF:rel_other=rel_" .. busy_metric
    for i, metric in ipairs ( metrics ) do
        if ( metric ~= busy_metric ) then
            cmd = cmd .. ",rel_" .. metric .. ",-"
        end
    end
    cmd = cmd .. "\" \\\n"

    cmd = cmd .. " \"CDEF:sum=rel_other"
    for i, metric in ipairs ( metrics ) do
        cmd = cmd .. ",rel_" .. metric .. ",+"
    end
    cmd = cmd .. "\" \\\n"

    cmd = cmd .. " \"CDEF:rel_idle=100,sum,-\" \\\n"

    local out_shape = shape
    -- print shapes and legends for each metric
    for i, metric in ipairs ( metrics ) do
        if ( stacked == '1' and i > 1 ) then
                out_shape = "STACK"
        end
        cmd = cmd .. rrd_metric_shape ( metric, stacked, out_shape, colors[i] )
        cmd = cmd .. rrd_metric_legend ( metric )
    end

    cmd = cmd .. " " .. out_shape .. ":rel_other" .. colors[#metrics+1] .. ":other"
    cmd = cmd .. rrd_metric_legend ( "other" )

    cmd = cmd .. " " .. out_shape .. ":rel_idle" .. colors[#metrics+2] .. ":idle"
    cmd = cmd .. rrd_metric_legend ( "idle" )

    -- print highlight for each metric
    out_shape = "LINE2"
    for i, metric in ipairs ( metrics ) do
        if ( stacked == '1' and i > 1 ) then
            out_shape = "STACK"
        end
        if ( shape == 'AREA' ) then
            cmd = cmd .. " " .. out_shape .. ":" .. "rel_" .. metric .. colors2[i] .. " \\\n"
        end
    end
    if ( stacked == '1' ) then
        cmd = cmd .. " " .. out_shape .. ":rel_other" .. colors2[#metrics+1] .. " \\\n"
    end

    -- execute rrdtool
    local rrdtool = io.popen( cmd )
    rrdtool:close()

    -- write command for debug
    nixio.fs.writefile("/tmp/rrdcmd.txt", cmd .. "\n" )
end


-- Controlling for the graph page.
--
-- since we use rrdtool1 (1.0.50) that doesn't provide lua bindings
-- we apply a shell command for rrd graph generation
function regmon_render()

    -- create the image
    local error_msg = ""

    local vars  = luci.http.formvalue()
    local spans = luci.util.split( uci.get( "luci_statistics", "collectd_rrdtool", "RRATimespans" ), "%s+", nil, true )
   	local span  = vars.timespan or uci.get( "luci_statistics", "rrdtool", "default_timespan" ) or spans[1]

    local metrics = uci.get("regmon", "regmon", "metrics") or {}
    local busy_metric = uci.get("regmon", "regmon", "busycounter") or {}
    local rrd_dir = uci.get("luci_statistics", "collectd_rrdtool", "DataDir") or "/tmp/rrd"
    local rrdimg_dir = uci.get("regmon","rrdtool","imagepath") or "/tmp/regmon"
    local hostname = luci.sys.hostname()
    local tailcsv_dir = "tail_csv-regmon"
    local rrdimg = "regmon.png"
    local img_width = uci.get( "regmon", "rrdtool", "width" ) or '800'
    local img_height = uci.get( "regmon", "rrdtool", "height" ) or '500'
    local stacked = uci.get( "regmon", "rrdtool", "stacked" ) or '1'
    local shape = uci.get( "regmon", "rrdtool", "shape" ) or 'AREA'

    -- fixme: check if exists before creating
    lfs.mkdir ( rrdimg_dir )
    
    generate_rrdimage ( rrdimg_dir .. "/" .. rrdimg
                      , span
                      , img_width
                      , img_height
                      , rrd_dir .. "/" .. hostname .. "/" .. tailcsv_dir
                      , metrics
                      , shape
                      , stacked
                      , busy_metric
                      )

       	-- deliver the image
  	if vars.img then
   		local l12 = require "luci.ltn12"
   		local png = io.open(rrdimg_dir .. "/" .. rrdimg, "r")
    	if png then
	    	luci.http.prepare_content("image/png")
		    l12.pump.all(l12.source.file(png), luci.http.write)
   		end
        local err = dbfiles
        l12.source.error(err)
    	return
   	end

    -- render page
    luci.template.render( "regmon/graph", {
        timespans        = spans,
        current_timespan = span,
		img              = "regmon.png",
        metrics          = metrics,
        error_msg        = error_msg
	} )

end