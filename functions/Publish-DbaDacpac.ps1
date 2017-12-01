Function Publish-DbaDacpac {
        <#
        .SYNOPSIS
        The Publish-Database CmdLet takes a dacpac which is the output from an SSDT project and publishes it to a database. 
        Changing the schema to match the dacpac and also to run any scripts in the dacpac (pre/post deploy scripts)
        .DESCRIPTION
               Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. 
               In 2016 the DacFx was supplied by Microsoft as a nuget package and this uses that nuget package.
        .PARAMETER dacpac
            Mandatory. DACPAC we are publishing from.
        .PARAMETER publishXml
            Mandatory. Publish profile which will include options and sqlCmdVariables.
        .PARAMETER targetConnectionString
            Mandatory. The connection string to the database you are upgrading.
        .PARAMETER targetDatabaseName
            Mandatory. The name of the database you are publishing.
        .PARAMETER GenerateDeploymentScript
            Mandatory. Determines whether or not to create publish script. 
        .PARAMETER GenerateDeploymentReport
            Mandatory. Determines whether or not to create publish xml report.
        .PARAMETER ScriptPath
            Optional. Required to output the files to.
        .PARAMETER ScriptOnly
            Optional. Specify this to create only the change scripts.
        .PARAMETER getSqlCmdVars
            Optional. If there are SqlCmdVars in the publish.xml that need to have their values overwritten, specify this Swtich to execute Get-SqlCmdVars.
        .PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: TAGS_HERE 
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
        .LINK
            https://dbatools.io/Test-Noun

        .EXAMPLE
            $svrConnstring = "SERVER=(localdb1)\MSSQLLocalDB;Integrated Security=True;Database=master"
            $output_NAME = "WideWorldImporters"
            $output = "C:\Users\Richie\Source\Repos\PoshSSDTBuildDeploy\tests\wwi-dw-ssdt"
            $output_SLN = Join-Path $output "\WideWorldImportersDW.sqlproj"
            $output_DAC = Join-Path $output "\Microsoft.Data.Tools.Msbuild\lib\net46"
            $output_DACFX = Join-Path $output_DAC "\Microsoft.SqlServer.Dac.dll"
            $output_DACPAC = Join-Path $output "\bin\Debug\WideWorldImportersDW.dacpac"
            $output_PUB = Join-Path $output "\bin\Debug\WideWorldImportersDW.publish.xml"
        Publish-DbaDacpac -dacpac $output_DACPAC -publishXml $output_PUB -targetConnectionString $svrConnstring -targetDatabaseName $output_NAME -GenerateDeploymentScript $true -GenerateDeployMentReport $true -ScriptPath $output -Verbose -EnableException

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $dacpac,
        [Parameter(Mandatory = $true)]
        $publishXml,
        [Parameter(Mandatory = $true)]
        $targetConnectionString,
        [Parameter(Mandatory = $true)]
        $targetDatabaseName,
        [Parameter(Mandatory = $true)] 
        [bool] $GenerateDeploymentScript,
        [Parameter(Mandatory = $true)]
        [bool] $GenerateDeploymentReport,
        $ScriptPath,
        [Switch] $ScriptOnly,
        [Switch] $getSqlCmdVars,
        [switch][Alias('Silent')]$EnableException
   )
    if ($ScriptPath) {
        if (-not (Test-Path $ScriptPath)) {
            
        }
    }
    $dacfxPath = ".\bin\DacFX\Microsoft.SqlServer.Dac.dll"
    if ((Test-Path $dacfxPath) -eq $false) {
        Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException
    }
    else {
        try {
            Add-Type -Path $dacfxPath
        }
        catch {
            Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException  -ErrorRecord $_
        }
    }
    if (Test-Path $dacpac) {
        $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Dacpac)
        }
    else {
        Stop-Function -Message  "$dacpac not found!"  -EnableException $EnableException
    }
    if (Test-Path $publishXml) {
        $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($publishXml)
    }
    else {
        Stop-Function -Message  "$publishXml not found!"  -EnableException $EnableException
    }
    if ($getSqlCmdVars -eq $true) {
        Get-SqlCmdVars $dacProfile.DeployOptions.SqlCommandVariableValues -EnableException
    }
    $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")    
    $DatabaseScriptPath = Join-Path $ScriptPath "$($targetDatabaseName)_DeployScript_$timeStamp.sql"
    $MasterDbScriptPath = Join-Path $ScriptPath "($targetDatabaseName)_Master.DeployScript_$timeStamp.sql"
    $DeploymentReport = Join-Path $ScriptPath "$targetDatabaseName.Result.DeploymentReport_$timeStamp.xml"

    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $targetConnectionString
    $options = @{
        GenerateDeploymentScript = $GenerateDeploymentScript
        GenerateDeploymentReport = $GenerateDeploymentReport
        DatabaseScriptPath       = $DatabaseScriptPath
        MasterDbScriptPath       = $MasterDbScriptPath
        DeployOptions            = $dacProfile.DeployOptions
    }
    try {
        Register-ObjectEvent -InputObject $dacServices -EventName "Message" -Source "msg" -Action { Write-Host $EventArgs.Message.Message } | Out-Null  
        if ($ScriptOnly) {
            if (($GenerateDeploymentScript -eq $false) -and ($GenerateDeploymentReport -eq $false)) {
                $ToThrow = "Specify at least one of GenerateDeploymentScript or GenerateDeploymentReport to be true when using ScriptOnly!"
            }
            else {
                Write-Message -Level Verbose -Message "Generating script..." 
                $result = $dacServices.script($dacPackage, $targetDatabaseName, $options)
            }
        }
        else {
            Write-Message -Level Verbose -Message "Executing Deployment..."     
            $result = $dacServices.publish($dacPackage, $targetDatabaseName, $options)
        }
    }  
    catch [Microsoft.SqlServer.Dac.DacServicesException] {
        $toThrow = ('Deployment failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
    finally {
        Unregister-Event -SourceIdentifier "msg"
        if ($toThrow) {
            Stop-Function -Message $toThrow  -EnableException $EnableException
        }
        if ($GenerateDeploymentReport -eq $true) {
            $result.DeploymentReport | Out-File $DeploymentReport
            Write-Message -Level Verbose -Message "Deployment Report - $DeploymentReport"
        }
        if ($GenerateDeploymentScript -eq $true) {
            Write-Message -Level Verbose -Message "Database change script - $DatabaseScriptPath"
            if ((Test-Path $MasterDbScriptPath) -eq $true) {
                Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)"
            }
        }
    }
}