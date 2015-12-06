[cmdletbinding()]
param(
    [switch]$publishtodev,

    [switch]$publishtoprod
)

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")


function Ensure-GeoffreyLoaded{
    [cmdletbinding()]
    param(
        [string]$minGeoffreyModuleVersion = '0.0.11-beta'
    )
    process{
        # load nuget-powershell if not already
        $geoffreyloaded = $false
        if((get-command Invoke-Geoffrey -ErrorAction SilentlyContinue)){
            if($env:GeoffreySkipReload -eq $true){
                $geoffreyloaded = $true
            }
            else{
                # check the module to ensure we have the correct version
                $currentversion = (Get-Module -Name geoffrey).Version
                if( ($currentversion -ne $null) -and ($currentversion.CompareTo([version]::Parse($minGeoffreyModuleVersion)) -ge 0 )){
                    $geoffreyloaded = $true
                }
            }
        }

        if(!$geoffreyloaded){
            (new-object Net.WebClient).DownloadString('https://raw.githubusercontent.com/geoffrey-ps/geoffrey/master/getgeoffrey.ps1') | Invoke-Expression
        }

        # verify it was loaded
        if(-not (get-command Invoke-Geoffrey -ErrorAction SilentlyContinue)){
            throw ('Unable to load geoffrey, unknown error')
        }
    }
}

Ensure-GeoffreyLoaded

$tasknames = @('build')

if($publishtodev){
    $tasknames += 'publishtodev'
}
if($publishtoprod){
    $tasknames += 'publishtoprod'
}

Invoke-Geoffrey -scriptPath (Join-Path $scriptDir 'gfile.ps1') -taskName $tasknames