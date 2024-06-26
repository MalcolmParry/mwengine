outputdir = "%{cfg.buildcfg}-%{cfg.system}-%{cfg.architecture}"
vulkanSDK = os.getenv("VULKAN_SDK")

project "mwengine"
    kind "StaticLib"
    language "C++"

    targetdir (_WORKING_DIR .. "/bin/" .. outputdir .. "/%{prj.name}")
    objdir (_WORKING_DIR .. "/bin/int/" .. outputdir .. "/%{prj.name}")

    files {
        "src/**.cpp",
        "src/**.h",
        "src/**.ipp",
        "mwengine.h"
    }

    includedirs {
        "./",
        "src/",
        vulkanSDK .. "/include"
    }

    defines {
        "MWENGINE"
	}

    links {
        "Logger",
        vulkanSDK .. "/Lib/vulkan-1.lib"
    }

    pchheader "pch.h"
    pchsource "src/pch.cpp"

    filter "system:windows"
        cppdialect "c++17"
        staticruntime "On"
        systemversion "latest"
    
    filter "configurations:Debug"
        defines "DEBUG"
        symbols "On"
    
    filter "configurations:Release"
        defines "RELEASE"
        optimize "On"

include "vendor/Logger"