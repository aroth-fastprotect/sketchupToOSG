# Copyright Iowa State University 2011, 2013, 2014
#
# Distributed under the Boost Software License, Version 1.0.
#
# (See accompanying file LICENSE_1_0.txt or copy at
# http://www.boost.org/LICENSE_1_0.txt)

if Sketchup.version_number < 14000000
	require "osgconv/fileutils.rb"
else
	require 'fileutils'
end

module RP_SketchUpToOSG
    # TODO de-duplication
    @osg_exportviacollada_extension_url = "https://github.com/rpavlik/sketchupToOSG#readme"

    def self.exportToOSG(selectionOnly, extension)
	    # Present an options dialog
	    prompts = ["Open in viewer after export?",
		    "Export edges?",
		    "Double-sided faces?",
            "Triangulate All Faces?",
            "Preserve Instancing?",
		    "Rotate to Y-UP?",
		    "Convert to output units:",
            "Use STATIC transform?"
            ]
	    defaults = ["no", "no", "no", "yes", "no", "no", "meters", "yes"]
	    list = ["yes|no", "yes|no", "yes|no", "yes|no", "yes|no", "yes|no", "inches (no scaling)|feet|meters", "yes|no"]
	    if extension == ".ive" or extension == ".osgb"
		    prompts << "Compress textures?"
		    defaults << "yes"
		    list << "yes|no"
	    end
	    input = UI.inputbox prompts, defaults, list, "OpenSceneGraph Export Options"

	    if input == nil
		    # If they cancelled the options dialog, don't export
		    return
	    end

	    # Interpret results of options dialog
	    view = (input[0] == "yes")
	    edges = (input[1] == "yes")
	    doublesided = (input[2] == "yes")
        doTriangulate = (input[3] == "yes")
        doPreserveInstancing = (input[4] == "yes")
	    doRotate = (input[5] == "yes")
	    doScale = (input[6] != "inches (no scaling)")
        scale_units = input[6]
	    doCompress = false
	    if extension == ".ive" or extension == ".osgb"
		    doCompress = (input[7] == "yes")
	    end
        useStaticTransform = (input[8] == "yes")

	    # Get model information
	    model = Sketchup.active_model
	    title = model.title

	    # Present "Save as" dialog
	    outputFn = UI.savepanel("Save to #{extension}...", nil, "#{title}#{extension}")
	    if outputFn == nil
		    # Don't export if they hit cancel
		    return
	    end
	    if File.extname(outputFn) == ""
		    # If specified filename had no extension, add the default.
		    outputFn = outputFn + extension
	    end

	    # Flag: don't delete the export texture dir if it already exists before export
	    skipDeleteDir = File.directory?(outputFn + "-export")

	    # Export to DAE
	    Sketchup.status_text = "Exporting to a temporary DAE file..."
	    tempFn = outputFn + "-export.dae"
        logfile = File.open(outputFn + ".log", "w")
	    options_hash = {:triangulated_faces   => doTriangulate,
					    :doublesided_faces    => doublesided,
					    :edges                => edges,
					    :materials_by_layer   => false,
					    :author_attribution   => true,
					    :texture_maps         => true,
					    :selectionset_only    => selectionOnly,
					    :preserve_instancing  => doPreserveInstancing,
                        :camera_lookat        => false}
        logfile.puts "Export to DAE options: " + options_hash.to_s
	    status = model.export tempFn, options_hash
	    if (not status)
		    UI.messagebox("Could not export to DAE")
            logfile.close
		    return
	    end

	    # Set up command line arguments
	    convertArgs = [tempFn,
		    outputFn,
		    "--use-world-frame",
		    "-O", "OutputRelativeTextures daeUseSequencedTextureUnits"]
		if extension == ".ive" or extension == ".osgb"
			convertArgs << "-O"
			convertArgs << "WriteImageHint=IncludeData"
		end
	    viewPseudoLoader = ""

	    if doScale
            scale = "1.0"
		    if scale_units == "meters"
			    scale = "0.02539999969303608" # inches to meters
		    elsif scale_units == "feet"
			    scale = "0.083333" # inches to feet
		    end
		    convertArgs << "-s"
		    convertArgs << "#{scale},#{scale},#{scale}"
	    end

	    if doRotate
		    convertArgs << '-o'
		    convertArgs << '0,0,1-0,1,0'
		    viewPseudoLoader = viewPseudoLoader + ".90,0,0.rot"
	    end

	    if doCompress
		    convertArgs << "--compressed"
	    end
        

	    # Tell OSG where it can find its plugins
	    ENV['OSG_LIBRARY_PATH'] = @osglibpath
		ENV['OSG_OPTIMIZER'] = 'DEFAULT,FLATTEN_STATIC_TRANSFORMS,FLATTEN_STATIC_TRANSFORMS_DUPLICATING_SHARED_SUBGRAPHS,MERGE_GEODES,VERTEX_POSTTRANSFORM,VERTEX_PRETRANSFORM,BUFFER_OBJECT_SETTINGS'
        if useStaticTransform
            ENV['OSG_OPTIMIZER'] = ENV['OSG_OPTIMIZER'] + 'PATCH_UNSPECIFIED_TRANSFORMS'
        end

        logfile.puts "Environment: "
        logfile.puts "OSG_LIBRARY_PATH=" + ENV['OSG_LIBRARY_PATH'].to_s
        logfile.puts "OSG_OPTIMIZER=" + ENV['OSG_OPTIMIZER'].to_s
        
	    # Change to output directory
	    outdir = File.dirname(outputFn)
	    Dir.chdir outdir do
		    # Run the converter
		    Sketchup.status_text = "Converting .dae temp file to OpenSceneGraph format..."
            logfile.puts "Converting .dae temp file to OpenSceneGraph format..."
            logfile.puts @osgconvbin, *convertArgs
		    status = Kernel.system(@osgconvbin, *convertArgs)

		    if not status
			    UI.messagebox("Failed when converting #{tempFn} to #{outputFn}! Temporary file not deleted, for your inspection.")
                logfile.close
			    return
		    end
	    end

	    # Delete temporary file(s)
	    File.delete(tempFn)
	    if not skipDeleteDir
		    FileUtils.rm_rf outputFn + "-export"
	    end

	    # View file if requested
	    extraMessage = ""
	    if view
		    Sketchup.status_text = "Launching viewer of exported model..."
            logfile.puts "Launching viewer of exported model..."
            logfile.puts @osgviewerbin, "--window", "50", "50", "640", "480", outputFn + viewPseudoLoader
		    Thread.new{ system(@osgviewerbin, "--window", "50", "50", "640", "480", outputFn + viewPseudoLoader) }
		    extraMessage = "Viewer launched - press Esc to close it."
	    end
        logfile.puts "Export of #{outputFn} successful!  #{extraMessage}"
        logfile.close

	    Sketchup.status_text = "Export of #{outputFn} successful!  #{extraMessage}"
    end

    def self.selectionValidation()
	    if Sketchup.active_model.selection.empty?
		    return MF_GRAYED
	    else
		    return MF_ENABLED
	    end
    end

    if( not file_loaded? __FILE__ )

	    # Find helper applications and directories
	    @plugindir = File.dirname( __FILE__ )
	    @osgbindir = (Object::RUBY_PLATFORM=~/mswin|x64-mingw32/)? @plugindir : @plugindir + '/vendor/bin'
	    @osglibpath = (Object::RUBY_PLATFORM=~/mswin|x64-mingw32/)?  @plugindir : @plugindir + '/vendor/lib/osgPlugins-3.5.6'
	    @binext = (Object::RUBY_PLATFORM=~/mswin|x64-mingw32/)? ".exe" : ""
	    @osgconvbin = @osgbindir + "/osgconv" + @binext
	    @osgviewerbin = @osgbindir + "/osgviewer" + @binext

	    if not File.exists?(@osgconvbin) or not File.exists?(@osgviewerbin)
		    UI.messagebox("Failed to find conversion/viewing tools!\nosgconv: #{@osgconvbin}\nosgviewer: #{@osgviewerbin}")
		    return
	    end

        osg_menu = UI.menu("File").add_submenu("Export to OpenSceneGraph")

	    osg_menu.add_item("Export entire document to IVE...") { self.exportToOSG(false, ".ive") }
		osg_menu.add_item("Export entire document to OSG binary...") { self.exportToOSG(false, ".osgb") }
        osg_menu.add_item("Export entire document to OSG XML...") { self.exportToOSG(false, ".osgx") }
	    osg_menu.add_item("Export entire document to OSG text...") { self.exportToOSG(false, ".osgt") }

	    osg_menu.add_separator

	    selItem = osg_menu.add_item("Export selection to IVE...") { self.exportToOSG(true, ".ive") }
	    osg_menu.set_validation_proc(selItem) {self.selectionValidation()}
		
	    selItem = osg_menu.add_item("Export selection to OSG binary...") { self.exportToOSG(true, ".osgb") }
	    osg_menu.set_validation_proc(selItem) {self.selectionValidation()}

	    selItem = osg_menu.add_item("Export selection to OSG XML...") { self.exportToOSG(true, ".osgx") }
	    osg_menu.set_validation_proc(selItem) {self.selectionValidation()}

	    selItem = osg_menu.add_item("Export selection to OSG text...") { self.exportToOSG(true, ".osgt") }
	    osg_menu.set_validation_proc(selItem) {self.selectionValidation()}

	    osg_menu.add_separator

	    osg_menu.add_item("Visit SketchupToOSG homepage") { UI.openURL(@osg_exportviacollada_extension_url) }

        file_loaded __FILE__
    end

end #module
