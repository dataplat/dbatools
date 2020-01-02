function Get-SqlCmdVars {
    <#
        .SYNOPSIS
            Retrieves the values of PowerShell parameters and updates values of SqlmdVars listed in the publish.xml.

        .DESCRIPTION
            Attempt to resolve SQLCmd variables via matching powershell variables explicitly defined in the current context.
            To try and avoid 'bad' default values getting deployed, block a deployment if we have SqlCmd variables that aren't defined in current context.
            Function has one reference and is executed when the "getSqlCmdVars" switch is included.
        .PARAMETER SqlCommandVariableValues
            Mandatory. The SqlCommandVariableValues from the DeployOptions property in the Microsoft.SqlServer.Dac.DacProfile
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT
        .LINK
            https://dbatools.io/Test-Noun

        .EXAMPLE
        Imagine content of MyDbProject.publish.xml is as follows -
        <?xml version="1.0" encoding="utf-8"?>
        <Project ToolsVersion="14.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
        <PropertyGroup>
            <IncludeCompositeObjects>True</IncludeCompositeObjects>
            <TargetDatabaseName>MyDbProject</TargetDatabaseName>
            <DeployScriptFileName>MyDbProject.sql</DeployScriptFileName>
            <TargetConnectionString>Data Source=.;Integrated Security=True;Persist Security Info=False;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True</TargetConnectionString>
            <BlockOnPossibleDataLoss>True</BlockOnPossibleDataLoss>
            <CreateNewDatabase>False</CreateNewDatabase>
            <ProfileVersionNumber>1</ProfileVersionNumber>
        </PropertyGroup>
        <ItemGroup>
            <SqlCmdVariable Include="DeployTag">
            <Value>OldValue</Value>
            </SqlCmdVariable>
        </ItemGroup>
        </Project>
        We will need one PowerShell parameter named $DeployTag to update the value

        The following scenario will fail as no $deployTag -
        "
            $publishXml =  "C:\MyDbProject\bin\Debug\MyDbProject.publish.xml"
            $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($publishXml)
            Get-SqlCmdVars $dacProfile.DeployOptions.SqlCommandVariableValues -EnableException
        "
        This scenario will pass.
        "
            $deployTag = "NewValue"
            $publishXml =  "C:\MyDbProject\bin\Debug\MyDbProject.publish.xml"
            $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($publishXml)
            Get-SqlCmdVars $dacProfile.DeployOptions.SqlCommandVariableValues -EnableException
        "
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        $SqlCommandVariableValues,
        [switch]$EnableException
    )
    $missingVariables = @()
    $keys = $($SqlCommandVariableValues.Keys)
    foreach ($var in $keys) {
        if (Test-Path variable:$var) {
            $value = Get-Variable $var -ValueOnly
            $SqlCommandVariableValues[$var] = $value
        } else {
            $missingVariables += $var
        }
    }
    if ($missingVariables.Count -gt 0) {
        $errorMsg = 'The following SqlCmd variables are not defined in the session (but are defined in the publish profile): {0}' -f ($missingVariables -join " `n")
        Stop-Function -Message $errorMsg -EnableException $EnableException
    }
}