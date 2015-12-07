$env:ExitOnPesterFail = $true
$env:IsDeveloperMachine=$true
$env:PesterEnableCodeCoverage = $true

$publishtodev = $false
$publishtoprod = $false

$prnumber = $env:APPVEYOR_PULL_REQUEST_NUMBER
$branch = $env:APPVEYOR_REPO_BRANCH

if(([string]::IsNullOrWhiteSpace($prnumber))){
    # it's not a PR now check branch
    if($branch -eq 'dev3'){
        $publishtodev=$true
    }
}

.\build.ps1 -publishtodev:$publishtodev -publishtoprod:$publishtoprod
