[cmdletbinding()]
param()

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")

$global:swbuildsettings = new-object -TypeName PSCustomObject @{
    OutputPath = (Join-Path $scriptDir 'OutputRoot')
    DnvmPath = "$env:USERPROFILE\.dnx\bin\dnvm.cmd"
    DnuPath = $null
    DnvmInstallUrl = 'https://raw.githubusercontent.com/aspnet/Home/dev/dnvminstall.ps1'
    GlobalJsonPath = (Join-Path $scriptDir global.json)
    WebsiteRoot = (Join-Path $scriptDir SideWaffleWebsite)
    NpmPath = "$env:APPDATA\npm"
    VsExternalsFolder = "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\Web Tools\External"
}

function InternalOverrideSettingsFromEnv{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [object[]]$settings = ($global:swbuildsettings),

        [Parameter(Position=1)]
        [string]$prefix = 'Publish'
    )
    process{
        foreach($settingsObj in $settings){
            if($settingsObj -eq $null){
                continue
            }

            $settingNames = $null
            if($settingsObj -is [hashtable]){
                $settingNames = $settingsObj.Keys
            }
            else{
                $settingNames = ($settingsObj | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)

            }

            foreach($name in ($settingNames.Clone())){
                $fullname = ('{0}{1}' -f $prefix,$name)
                if(Test-Path "env:$fullname"){
                    $settingsObj.$name = ((get-childitem "env:$fullname").Value)
                }
            }
        }
    }
}

InternalOverrideSettingsFromEnv -prefix 'swbuild' -settings $global:swbuildsettings

task default -dependsOn build

task init{
    requires -nameorurl psbuild -version '1.1.6-beta' -noprefix -condition (-not (Get-Command -Module psbuild -Name Invoke-MSBuild -ErrorAction SilentlyContinue) )
    
    if(-not(Test-Path $global:swbuildsettings.OutputPath)){
        New-Item -ItemType Directory -Path $global:swbuildsettings.OutputPath
    }

    if(-not (Test-Path $global:swbuildsettings.WebsiteRoot)){
        throw ('Website root not found at [{0}]' -f $global:swbuildsettings.WebsiteRoot)
    }
} -dependsOn initdnvm,inittools

task initdnvm {   
    requires -nameorurl $global:swbuildsettings.DnvmInstallUrl -condition (-not (Test-Path $global:swbuildsettings.DnvmPath))

    if(-not (Test-Path $global:swbuildsettings.DnvmPath)){
        throw ('unable to install dnvm to path [{0}]' -f $global:swbuildsettings.DnvmPath)
    }

    [System.IO.FileInfo]$dnvmpath = $global:swbuildsettings.DnvmPath
    # Set-Alias dnvm $global:swbuildsettings.DnvmPath

    $globaljsonversion = GetVersionFromGlobalJson -globalJsonPath $global:swbuildsettings.GlobalJsonPath
    if([string]::IsNullOrWhiteSpace($globaljsonversion)){
        throw ('unable to read version from global.json at [{0}]' -f $global:swbuildsettings.GlobalJsonPath)
    }

    # ensure the runtime is installed with dnvm install
    Invoke-CommandString -command $dnvmpath.FullName -commandArgs @('install',$globaljsonversion)

    # use that version
    Invoke-CommandString -command $dnvmpath.FullName -commandArgs @('use',$globaljsonversion)

    # set the dnupath
    [System.IO.FileInfo]$dnupath = "$env:USERPROFILE\.dnx\runtimes\dnx-clr-win-x86.$globaljsonversion\bin\dnu.cmd"
    if(-not (Test-Path $dnupath.FullName)){
        throw ('dnu not found at [{0}]' -f $dnupath)
    }
    $global:swbuildsettings.DnuPath = $dnupath
}

task inittools{
    # add npm folder to path
    if(-not (test-path $global:swbuildsettings.NpmPath)){
        throw ('npm folder not found at [{0}]' -f $global:swbuildsettings.NpmPath)
    }

    Add-Path -pathToAdd $global:swbuildsettings.NpmPath

    if(-not (Test-Path $global:swbuildsettings.VsExternalsFolder)){
        throw ('vs externals folder not found at [{0}]' -f $global:swbuildsettings.VsExternalsFolder)
    }
    # C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\Web Tools\External
    Add-Path $global:swbuildsettings.VsExternalsFolder
    Add-Path (join-path $global:swbuildsettings.VsExternalsFolder 'git')
    Add-Path (join-path $global:swbuildsettings.VsExternalsFolder 'node')
}

task build{
    
    Push-Location
    try{
        Set-Location $global:swbuildsettings.WebsiteRoot

        # restore
        'Restoring packages' | Write-Output
        Invoke-CommandString -command $global:swbuildsettings.DnuPath -commandArgs @('restore')

        # build
        'Building the project' | Write-Output
        Invoke-CommandString -command $global:swbuildsettings.DnuPath -commandArgs @('build')
    }
    finally{
        Pop-Location
    }
}

function GetVersionFromGlobalJson{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [System.IO.FileInfo]$globalJsonPath
    )
    process{
        if($globalJsonPath -eq $null){ throw ('globaljsonpath is null') }
        if(-not (Test-Path $globalJsonPath.FullName)){ throw ('global.json not found at [{0}]' -f $globalJsonPath.FullName) }
        
        try{
            $globaljson = ConvertFrom-Json ([System.IO.File]::ReadAllText($globaljsonpath.FullName))                                                                             
            $version = $globaljson.sdk.version                                                                                                                                   
        }
        catch{
            # do nothing, return nothing
        }

        # return the version string
        $version
    }
}

function Add-Path{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,Position=0)]
        [string[]]$pathToAdd
    )

    # Get the current search path from the environment keys in the registry.
    $oldpath=$env:path
    if (!$pathToAdd){
        ‘No Folder Supplied. $env:path Unchanged’ | Write-Verbose
    }
    elseif (!(test-path $pathToAdd)){
        ‘Folder [{0}] does not exist, Cannot be added to $env:path’ -f $pathToAdd | Write-Verbose
    }
    elseif ($env:path | Select-String -SimpleMatch $pathToAdd){
        Return ‘Folder already within $env:path' | Write-Verbose
    }
    else{
        'Adding [{0}] to the path' -f $pathToAdd | Write-Verbose
        $newpath = $oldpath
        # set the new path
        foreach($path in $pathToAdd){
            $newPath += ";$path"
        }

        $env:path = $newPath
        [Environment]::SetEnvironmentVariable('path',$newPath,[EnvironmentVariableTarget]::Process) | Out-Null
    }
}

function Invoke-CommandString2{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,
        
        [Parameter(Position=1)]
        $commandArgs,

        $ignoreErrors,

        [bool]$maskSecrets
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose
            
            # write it to a .cmd file
            $destPath = "$([System.IO.Path]::GetTempFileName()).cmd"
            if(Test-Path $destPath){Remove-Item $destPath|Out-Null}
            
            try{
                @'
set path={0}
"{1}" {2}
'@ -f $env:Path, $cmdToExec, ($commandArgs -join ' ') | Set-Content -Path $destPath | Out-Null

                $actualCmd = ('"{0}"' -f $destPath)
                if($maskSecrets){
                    cmd.exe /D /C $actualCmd | Write-Output
                }
                else{
                    cmd.exe /D /C $actualCmd
                }

                if(-not $ignoreErrors -and ($LASTEXITCODE -ne 0)){
                    $msg = ('The command [{0}] exited with code [{1}]' -f $cmdToExec, $LASTEXITCODE)
                    throw $msg
                }
            }
            finally{
                if(Test-Path $destPath){Remove-Item $destPath -ErrorAction SilentlyContinue |Out-Null}
            }
        }
    }
}