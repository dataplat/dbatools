<# loop through all files in the tests directory that matches HaveParameter
$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = "When testing HaveParameter, we should have used type full names and we used type short names.Consult types.md and apply the appropriate replacements. Do not remove any arrays ([]), just replace the type names."


foreach ($test in $tests) {
    Write-Host "Processing $test"
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream --cache-prompts --read /workspace/.aider/prompts/types.md
}

$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = "This is a Pester v5 test suite. 1. Remove -Type test in HaveParameter tests. 2. Remove -Mandatory test in HaveParameter test. 2. Remove all -Mandatory:`$false from the HaveParameter test."


foreach ($test in $tests) {
    Write-Host "Processing $test"
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream
}


----------------

$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = 'HaveParameter tests must be structured exactly like this:

        $params = @(
            "SqlInstance",
            "SqlCredential"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }'


foreach ($test in $tests) {
    Write-Host "Processing $test"
    if ((Get-Content $test.FullName | Select-String -SimpleMatch -Pattern 'has the required parameter: <_>" -ForEach')) {
        Write-Host "Skipping $($test.Name) because it already has the correct structure"
        continue
    }
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream
}
#>

param (
    [int]$First = 1000,
    [int]$Skip = 0
)
# Full prompt path
if (-not (Get-Module dbatools.library -ListAvailable)) {
    Write-Warning "dbatools.library not found, installing"
    Install-Module dbatools.library -Scope CurrentUser -Force
}
Import-Module /workspace/dbatools.psm1

$promptTemplate = '
        Required parameters for this command:
        --PARMZ--

        AND HaveParameter tests must be structured exactly like this:

        $params = @(
            "parameter1",
            "parameter2",
            "etc"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }

        NO OTHER CHANGES SHOULD BE MADE TO THE TEST FILE'

$commands = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
$commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

foreach ($command in $commands) {
    $cmdName = $command.Name
    $filename = "/workspace/tests/$cmdName.Tests.ps1"

    if (-not (Test-Path $filename)) {
        Write-Warning "No tests found for $cmdName"
        Write-Warning "$filename not found"
        continue
    }

    $parameters = $command.Parameters.Values | Where-Object Name -notin $commonParameters

    $parameters = $parameters.Name -join ", "
    $cmdPrompt = $promptTemplate -replace "--PARMZ--", $parameters

    # Run Aider in non-interactive mode with auto-confirmation
    aider --message "$cmdPrompt" --file $filename --yes-always --no-stream --model azure/gpt-4o-mini
}
# <_>
# It "has the required parameter: <$_>" -ForEach $params { # 2
# It "has the required parameter: $_" # 25
# It "has all the required parameters" -ForEach $requiredParameters {
# Copy-DbaDbViewData.Tests.ps1: $params | ForEach-Object {
# It "has the required parameter: SqlInstance" -ForEach $params { 7
# It "has the required parameter: $_" -ForEach $params {
# It "has the required parameter: $_" -ForEach $params {
# It "has the required parameter: SqlInstance" -ForEach $params {
# It "has the required parameter: $_" -ForEach $params {
# It "has the required parameter: $_" -ForEach $params {
# It "has the required parameter: $_" -ForEach $params {

<#
        BeforeDiscovery {
            [object[]]$params = (Get-Command Copy-DbaDatabase).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        }

#>