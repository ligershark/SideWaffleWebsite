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
    PackOutput = (Join-Path $scriptDir 'OutputRoot\packout')
    DnvmPath = "$env:USERPROFILE\.dnx\bin\dnvm.cmd"    
    Configuration = 'Release'
    DnvmInstallUrl = 'https://raw.githubusercontent.com/aspnet/Home/dev/dnvminstall.ps1'
    GlobalJsonPath = (Join-Path $scriptDir global.json)
    WebsiteRoot = (Join-Path $scriptDir 'SideWaffleWebsite')
    NpmPath = "$env:APPDATA\npm"
    VsExternalsFolder = "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\Web Tools\External"
    PublishModuleVersion = '1.0.2-beta2'
    DnuPath = $null
    GlobalJsonVersion = $null
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

task init -dependsOn coreinit, initdnvm, inittools

task coreinit{
    'checking for psbuild' | Write-Output
    requires -nameorurl psbuild -version '1.1.7-beta' -noprefix -condition (-not (Get-Command -Module psbuild -Name Invoke-MSBuild -ErrorAction SilentlyContinue) )
    
    if(-not ([string]::IsNullOrWhiteSpace($global:swbuildsettings.OutputPath)) -and (Test-Path $global:swbuildsettings.OutputPath)){
        Remove-Item $global:swbuildsettings.OutputPath -Recurse -Force
    }

    if(-not(Test-Path $global:swbuildsettings.OutputPath)){
        New-Item -ItemType Directory -Path $global:swbuildsettings.OutputPath
    }

    if(-not(Test-Path $global:swbuildsettings.PackOutput)){
        New-Item -ItemType Directory -Path $global:swbuildsettings.PackOutput
    }

    if(-not (Test-Path $global:swbuildsettings.WebsiteRoot)){
        throw ('Website root not found at [{0}]' -f $global:swbuildsettings.WebsiteRoot)
    }
}

task initdnvm {   
    requires -nameorurl $global:swbuildsettings.DnvmInstallUrl -condition (-not (Test-Path $global:swbuildsettings.DnvmPath))

    if(-not (Test-Path $global:swbuildsettings.DnvmPath)){
        throw ('unable to install dnvm to path [{0}]' -f $global:swbuildsettings.DnvmPath)
    }

    [System.IO.FileInfo]$dnvmpath = $global:swbuildsettings.DnvmPath
    # Set-Alias dnvm $global:swbuildsettings.DnvmPath
    
    $global:swbuildsettings.GlobalJsonVersion = GetVersionFromGlobalJson -globalJsonPath $global:swbuildsettings.GlobalJsonPath
    if([string]::IsNullOrWhiteSpace($global:swbuildsettings.GlobalJsonVersion)){
        throw ('unable to read version from global.json at [{0}]' -f $global:swbuildsettings.GlobalJsonPath)
    }

    # ensure the runtime is installed with dnvm install
    Invoke-CommandString -command $dnvmpath.FullName -commandArgs @('install',$global:swbuildsettings.GlobalJsonVersion)

    # use that version
    Invoke-CommandString -command $dnvmpath.FullName -commandArgs @('use',$global:swbuildsettings.GlobalJsonVersion)

    $globaljsonversion = $global:swbuildsettings.GlobalJsonVersion
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
        Invoke-CommandString -command npm -commandArgs @('install','-g','gulp')
        Add-Path -pathToAdd "$env:APPDATA\npm"
        $env:NODE_PATH=(join-path "$env:APPDATA" 'npm\node_modules')

        Invoke-CommandString -command $global:swbuildsettings.DnuPath -commandArgs @('restore')

        Add-Path -pathToAdd (Join-Path $scriptDir 'SideWaffleWebsite\node_modules\.bin')

        # build
        'Building the project' | Write-Output
        Invoke-CommandString -command $global:swbuildsettings.DnuPath -commandArgs @('build')
    }
    finally{
        Pop-Location
    }
}

task localpublish{
    # dnu publish --out C:\data\mycode\SideWaffleWebsite\OutputRoot\packout --configuration Release --runtime dnx-clr-win-x86.1.0.0-rc1-update1 --wwwroot "wwwroot" --iis-command "web"
    Push-Location
    try{
        Set-Location $global:swbuildsettings.WebsiteRoot        
        $dnupubargs = @('publish','--out',$global:swbuildsettings.PackOutput,'--configuration',$global:swbuildsettings.Configuration,'--runtime',('dnx-clr-win-x86.{0}' -f $global:swbuildsettings.GlobalJsonVersion),'--wwwroot','"wwwroot"','--iis-command','"web"')
        'calling dnu publish with the following args [{0}]' -f ($dnupubargs -join ' ' ) | Write-Output
        Invoke-CommandString -command $global:swbuildsettings.DnuPath -commandArgs $dnupubargs
    }
    finally{
        Pop-Location
    }
} -dependsOn build

task installpublishmodule{
    'Ensuring publish-module version "{0}" is loaded' -f $global:swbuildsettings.PublishModuleVersion | Write-Output
    requires -nameorurl publish-module -version $global:swbuildsettings.PublishModuleVersion -noprefix -condition (-not (Get-Command -Module publish-module -Name Publish-AspNet -ErrorAction SilentlyContinue) )
}

task publishtodev{
    'Publishing to latest.sidewaffle.com' | Write-Output
    PublishToRemote -packoutput $global:swbuildsettings.PackOutput -publishProperties (GetPublishProperties -site latest)
} -dependsOn localpublish, installpublishmodule

task publishtoprod{
} -dependsOn localpublish, installpublishmodule

function GetPublishProperties{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateSet('latest','prod')]
        [string]$site
    )
    process{
        [hashtable]$pubprops = $null

        switch($site){
            'latest' {
                $pubprops = @{
                    'WebPublishMethod'='MSDeploy'
                    'MSDeployServiceUrl'='sidewaffle.scm.azurewebsites.net:443'
                    'DeployIISAppPath'='sidewaffle'
                    'Username'=$env:publishusername
                    'Password'=$env:publishpwd
                }
            }

            'prod' {
                throw ('Not yet implemented')
            }

            default {
                throw ('Unknown value for site [{0}]' -f $site)
            }
        }

        if([string]::IsNullOrWhiteSpace($pubprops.Username)){
            throw ('Missing required value for username (define in $env:publishusername)')
        }
        if([string]::IsNullOrWhiteSpace($pubprops.Password)){
            throw ('Missing required value for username (define in $env:publishpwd)')
        }

        # return the object here
        $pubprops
    }
}

function PublishToRemote{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo]$packoutput = $global:swbuildsettings.PackOutput,

        [Parameter(Position=1,Mandatory=$true)]
        [hashtable]$publishProperties
    )
    process{
        try{
            Publish-AspNet -packoutput $packoutput.FullName -publishProperties $publishProperties
        }
        catch{
            'An error occurred during publish' | Write-Error
        }
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
