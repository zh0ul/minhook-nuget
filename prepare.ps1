﻿# This script prepares all the required files for the NuGet package.
# * .targets file
# * Header file
# * Static library files

$ErrorActionPreference = "Stop"

################################################################################
# Definitions

# MSBuild Settings

Set-Variable -Name Toolsets -Option Constant -Value @(
    "v90", "v100", "v110", "v120"
)

Set-Variable -Name Platforms -Option Constant -Value @(
    "Win32", "x64"
)

Set-Variable -Name RuntimeLinks -Option Constant -Value @(
    "MD", "MT"
)

Set-Variable -Name Configs -Option Constant -Value @(
    "Debug", "Release"
)

################################################################################
# Functions

# Print message with time.

function showMsg($msg)
{
    $d = Get-Date -Format "HH:mm:ss"
    Write-Host "[$d] " -ForegroundColor Yellow -NoNewLine
    Write-Host "$msg " -ForegroundColor Green
}

# Download a file from the internet.

function download($url, $dir)
{
    $wc = New-Object System.Net.WebClient

    $f = Join-Path $dir (Split-Path $url -Leaf)
    $wc.DownloadFile($url, $f)

    return $f;
}

# Extract a ZIP file.

function extract($path)
{
    $e = Join-Path (Get-Location) "tools\7za.exe"
    $d = Split-Path $path -Parent
    $f = Split-Path $path -Leaf
    execute $e "x ""$f""" $d
}

# Execute a command.

function execute($exe, $params, $dir)
{
    # It looks like WaitForExit() is more stable than -Wait.

    $proc = Start-Process $exe $params -WorkingDirectory $dir `
        -NoNewWindow -PassThru
    $proc.WaitForExit()
}

################################################################################
# Main

$thisDir = Split-Path $script:myInvocation.MyCommand.path -Parent

# Read the settings.

$tempDir    = ""
$msbuildExe = ""

$lines = Get-Content (Join-Path $thisDir "prepare.ini") -Encoding UTF8
foreach ($line in $lines) {
    $s = $line.split("=").Trim()
    if ($s[0] -eq "TempDir") {
        $tempDir = $s[1]
    }
    elseif ($s[0] -eq "MSBuildExe") {
        $msbuildExe = $s[1]
    }
}

if ($tempDir -eq "" -or $msbuildExe -eq "") {
    showMsg("Error reading prepare.ini!")
    exit
}

# Locate the necessary files.

$sourceDir  = Join-Path $tempDir "source"
$minhookDir = Join-Path $thisDir "src\minhook"

$workBaseDir  = Join-Path $tempDir "work"
$libBaseDir   = Join-Path $thisDir "package\lib\native"
$buildBaseDir = Join-Path $thisDir "package\build\native"

# Download and extract the source files if not found.

if (-not (Test-Path $sourceDir)) {
    New-Item -Path $sourceDir -ItemType directory | Out-Null
}

if (Test-Path $workBaseDir) {
    Remove-Item -Path $workBaseDir -Recurse -Force
}

if (Test-Path $libBaseDir) {
    Remove-Item -Path $libBaseDir -Recurse -Force
}

if (Test-Path $buildBaseDir) {
    Remove-Item -Path $buildBaseDir -Recurse -Force
}

# Copy the header files which should be installed.

$headerSrcDir = Join-Path $minhookDir "include"
$headerDstDir = Join-Path $libBaseDir "include"

New-Item -Path $headerDstDir -ItemType directory | Out-Null
Copy-Item (Join-Path $headerSrcDir "*.h") $headerDstDir

# Begin creating the targets file.

$targetsContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Project ToolVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup>
    <ClCompile>
      <AdditionalIncludeDirectories>`$(MSBuildThisFileDirectory)..\..\lib\native\include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
    <Link>
      <AdditionalDependencies>`$(MSBuildThisFileDirectory)..\..\lib\native\lib\libMinHook.lib;%(AdditionalDependencies)</AdditionalDependencies>
    </Link>
  </ItemDefinitionGroup>

  <Target Name="BeforeClCompile">

    <!-- Check if the runtime link is dynamic or static -->

    <CreateProperty Value="%(ClCompile.RuntimeLibrary)">
      <Output TaskParameter="Value" PropertyName="MH_RuntimeLibrary" />
    </CreateProperty>

    <!-- MH_RuntimeLink corresponds to /MDd, /MD, /MTd and /MT options -->

    <CreateProperty Condition="(`$(MH_RuntimeLibrary.ToLower().IndexOf('dll')) &gt; -1) And (`$(Configuration.ToLower().IndexOf('debug')) &gt; -1)" Value="mdd">
      <Output TaskParameter="Value" PropertyName="MH_RuntimeLink" />
    </CreateProperty>
    <CreateProperty Condition="(`$(MH_RuntimeLibrary.ToLower().IndexOf('dll')) &gt; -1) And (`$(Configuration.ToLower().IndexOf('debug')) == -1)" Value="md">
      <Output TaskParameter="Value" PropertyName="MH_RuntimeLink" />
    </CreateProperty>
    <CreateProperty Condition="(`$(MH_RuntimeLibrary.ToLower().IndexOf('dll')) == -1) And (`$(Configuration.ToLower().IndexOf('debug')) &gt; -1)" Value="mtd">
      <Output TaskParameter="Value" PropertyName="MH_RuntimeLink" />
    </CreateProperty>
    <CreateProperty Condition="(`$(MH_RuntimeLibrary.ToLower().IndexOf('dll')) == -1) And (`$(Configuration.ToLower().IndexOf('debug')) == -1)" Value="mt">
      <Output TaskParameter="Value" PropertyName="MH_RuntimeLink" />
    </CreateProperty>

    <!-- MH_ToolSet is toolset except for "_xp" suffix. -->

    <CreateProperty Condition="`$(PlatformToolset.ToLower().IndexOf('v90')) == 0" Value="v90">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>
    <CreateProperty Condition="`$(PlatformToolset.ToLower().IndexOf('v100')) == 0" Value="v100">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>
    <CreateProperty Condition="`$(PlatformToolset.ToLower().IndexOf('v110')) == 0" Value="v110">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>
    <CreateProperty Condition="`$(PlatformToolset.ToLower().IndexOf('v120')) == 0" Value="v120">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>

    <!-- Special Cases: Windows Driver Kit -->

    <CreateProperty Condition="`$(PlatformToolset.ToLower()) == 'windowsapplicationfordrivers8.0'" Value="v110">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>
    <CreateProperty Condition="`$(PlatformToolset.ToLower()) == 'windowsapplicationfordrivers8.1'" Value="v120">
      <Output TaskParameter="Value" PropertyName="MH_ToolSet" />
    </CreateProperty>

    <!-- MH_Platform is CPU architecture. "x86" or "x64". -->

    <CreateProperty Condition="`$(Platform.ToLower()) == 'win32'" Value="x86">
      <Output TaskParameter="Value" PropertyName="MH_Platform" />
    </CreateProperty>
    <CreateProperty Condition="`$(Platform.ToLower()) == 'x64'" Value="x64">
      <Output TaskParameter="Value" PropertyName="MH_Platform" />
    </CreateProperty>

    <!-- Suffix of lib file like 'x86-v100-mdd' -->

    <CreateProperty Value="`$(MH_Platform)-`$(MH_ToolSet)-`$(MH_RuntimeLink)">
      <Output TaskParameter="Value" PropertyName="MH_LibSuffix" />
    </CreateProperty>


"@

# Go through all the platforms, toolsets and configurations.

$count = $Platforms.Length * $Toolsets.Length * $RuntimeLinks.Length * $Configs.Length
$i = 1

:toolset foreach ($toolset in $Toolsets)
{
    foreach ($platform in $Platforms)
    {
        foreach ($runtime in $RuntimeLinks)
        {
            foreach ($config in $Configs)
            {
                showMsg "Start Buiding [$toolset, $platform, $runtime, $config] ($i/$count)"

                # MsBuild parameters.
                $vsVer = ""
                if ($toolset -eq "v90") {
                    $vsVer = "10.0"
                }
                else {
                    $vsVer = $toolset.Substring(1, 2) + ".0"
                }

                $toolsetSuffix = "";
                if ([int]$vsVer -ge 11) {
                    $toolsetSuffix = "_xp";
                }

                $runtimeLib = "MultiThreaded"
                if ($config -eq "Debug") {
                    $runtimeLib += "Debug"
                }
                if ($runtime -eq "MD") {
                    $runtimeLib += "DLL"
                }

                $arch = ""
                if ($platform -eq "Win32") {
                    $arch = "x86"
                }
                else {
                    $arch = "x64"
                }

                $libSuffix = "$arch-$toolset-$runtime".ToLower()
                if ($config -eq "Debug") {
                    $libSuffix += "d"
                }

                # Build MinHook as a static library.

                $minhookProject = ""
                $minhookProject = Join-Path $minhookDir "build\vc12\libminhook.vcxproj"

                # I couldn't override some propreties of the TagLib project with
                # MSBuild for some reason. So modify the project file directly.

                $content = (Get-Content -Path $minhookProject -Encoding UTF8)
                $content = $content -Replace `
                    "<DebugInformationFormat>.*</DebugInformationFormat>", `
                    "<DebugInformationFormat></DebugInformationFormat>"
                $content = $content -Replace `
                    "<MinimalRebuild>.*</MinimalRebuild>", `
                    "<MinimalRebuild>false</MinimalRebuild>"
                $content = $content -Replace `
                    "<RuntimeLibrary>.*</RuntimeLibrary>", `
                    "<RuntimeLibrary>$runtimeLib</RuntimeLibrary>"

                if ($toolset -eq "v90") {
                    $content = $content -Replace `
                        "<EnableEnhancedInstructionSet>.*</EnableEnhancedInstructionSet>", `
                        ""
                }

                $content | Set-Content -Path $minhookProject -Encoding UTF8

                $params  = """$minhookProject"" "
                $params += "/p:VisualStudioVersion=$vsVer "
                $params += "/p:PlatformToolset=$toolset$toolsetSuffix "
                $params += "/p:Platform=$platform "
                $params += "/p:Configuration=$config "
                $params += "/p:TargetName=libMinHook-$libSuffix "
                $params += "/m "
                execute $msbuildExe $params $minhookDir

                $condition = "`$(MH_LibSuffix) == '$libSuffix'"
                $libPath = "..\..\lib\native\lib\libMinHook-$libSuffix.lib"

                $targetsContent += @"
    <Copy Condition="$condition" SourceFiles="`$(MSBuildThisFileDirectory)$libPath" DestinationFiles="`$(MSBuildThisFileDirectory)..\..\lib\native\lib\libMinHook.lib" />

"@
                $i++;
            }
        }
    }
}

# Copy necessary files.

$libDstDir = Join-Path $libBaseDir "lib"
New-Item -Path $libDstDir -ItemType directory | Out-Null

$libSrcDir = Join-Path $minhookDir "build\VC12\lib\Debug"
Copy-Item (Join-Path $libSrcDir "*.lib") $libDstDir
$libSrcDir = Join-Path $minhookDir "build\VC12\lib\Release"
Copy-Item (Join-Path $libSrcDir "*.lib") $libDstDir

# Finish creating the targets file.

$targetsContent += @"
  </Target>
</Project>

"@

New-Item -Path $buildBaseDir -ItemType directory | Out-Null
[System.IO.File]::WriteAllText( `
    (Join-Path $buildBaseDir "minhook.targets"), $targetsContent)

