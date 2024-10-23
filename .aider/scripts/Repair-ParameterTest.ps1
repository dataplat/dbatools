function Repair-ParameterTest {
    [cmdletbinding()]
    param (
        [int]$First = 1000,
        [int]$Skip = 0,
        [string]$Model = "azure/gpt-4o-mini"
    )
    # Full prompt path
    if (-not (Get-Module dbatools.library -ListAvailable)) {
        Write-Warning "dbatools.library not found, installing"
        Install-Module dbatools.library -Scope CurrentUser -Force
    }
    Import-Module /workspace/dbatools.psm1 -Force

    $promptTemplate = '
            Required parameters for this command:
            --PARMZ--

            AND HaveParameter tests must be structured EXACTLY like this:

            $params = @(
                "parameter1",
                "parameter2",
                "etc"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $currentTest | Should -HaveParameter $PSItem
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
        $params = @(
            "--message", $cmdPrompt,
            "--file", $filename,
            "--yes-always",
            "--no-stream",
            "--model", $Model
        )
        aider @params
    }
    <#
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
    #>
}