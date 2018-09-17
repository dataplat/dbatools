function Publish-DbaDacpac {
    <#
        .SYNOPSIS
            The Publish-Database command takes a dacpac which is the output from an SSDT project and publishes it to a database. Changing the schema to match the dacpac and also to run any scripts in the dacpac (pre/post deploy scripts).

        .DESCRIPTION
            Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. In 2016 the DacFx was supplied by Microsoft as a nuget package and this uses that nuget package.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            Specifies the filesystem path to the DACPAC

        .PARAMETER PublishXml
            Specifies the publish profile which will include options and sqlCmdVariables.

        .PARAMETER Database
            Specifies the name of the database being published.

        .PARAMETER ConnectionString
            Specifies the connection string to the database you are upgrading. This is not required if SqlInstance is specified.

        .PARAMETER GenerateDeploymentScript
            If this switch is enabled, the publish script will be generated.

        .PARAMETER GenerateDeploymentReport
            If this switch is enabled, the publish XML report  will be generated.

        .PARAMETER OutputPath
            Specifies the filesystem path (directory) where output files will be generated.

        .PARAMETER ScriptOnly
            If this switch is enabled, only the change scripts will be generated.

        .PARAMETER IncludeSqlCmdVars
            If this switch is enabled, SqlCmdVars in publish.xml will have their values overwritten.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER DacFxPath
            Path to the dac dll. If this is ommited, then the version of dac dll which is packaged with dbatools is used.

        .NOTES
            Tags: Migration, Database, Dacpac
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Publish-DbaDacpac

        .EXAMPLE
            Publish-DbaDacpac -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml

            Updates WideWorldImporters on sql2017 from the sql2016-WideWorldImporters.dacpac using the sql2016-WideWorldImporters-publish.xml publish profile

        .EXAMPLE
            New-DbaPublishProfile -SqlInstance sql2016 -Database db2 -Path C:\temp
            Export-DbaDacpac -SqlInstance sql2016 -Database db2 | Publish-DbaDacpac -PublishXml C:\temp\sql2016-db2-publish.xml -Database db1, db2 -SqlInstance sql2017

            Creates a publish profile at C:\temp\sql2016-db2-publish.xml, exports the .dacpac to $home\Documents\sql2016-db2.dacpac
            then publishes it to the sql2017 server database db2
        
        .EXAMPLE
        $loc = "C:\Users\bob\source\repos\Microsoft.Data.Tools.Msbuild\lib\net46\Microsoft.SqlServer.Dac.dll"
        Publish-DbaDacpac -SqlInstance "local" -Database WideWorldImporters -Path C:\temp\WideWorldImporters.dacpac -PublishXml C:\temp\WideWorldImporters.publish.xml -DacFxPath $loc
  #>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$PublishXml,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$Database,
        [string[]]$ConnectionString,
        [switch]$GenerateDeploymentScript,
        [switch]$GenerateDeploymentReport,
        [Switch]$ScriptOnly,
        [string]$OutputPath = "$home\Documents",
        [switch]$IncludeSqlCmdVars,
        [switch]$EnableException,
        [String]$DacFxPath
    )

    begin {
        if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString."
        }
        if ((Test-Bound -ParameterName GenerateDeploymentScript) -or (Test-Bound -ParameterName GenerateDeploymentReport)) {
            $defaultcolumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions', 'SqlCmdVariableValues'
        }
        else {
            $defaultcolumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DeployOptions', 'SqlCmdVariableValues'
        }
        if ((Test-Bound -ParameterName ScriptOnly) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript)) {
            Stop-Function -Message "You must at least one of GenerateDeploymentScript or GenerateDeploymentReport when using ScriptOnly"
        }

        function Get-ServerName ($connstring) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connstring)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '-').Replace('(','').Replace(')','')
        }
        if (Test-Bound -Not -ParameterName 'DacfxPath'){
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
        }

        if ((Test-Path $dacfxPath) -eq $false) {
            Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException
        }
        else {
            try {
                Add-Type -Path $dacfxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded."
            }
            catch {
                Stop-Function -Message 'No usable version of Dac Fx found.' -EnableException $EnableException -ErrorRecord $_
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path not found!"
        }

        if (-not (Test-Path -Path $PublishXml)) {
            Stop-Function -Message "$PublishXml not found!"
        }

        foreach ($instance in $sqlinstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'")
        }

        try {
            $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
        }
        catch {
            Stop-Function -Message "Could not load package." -ErrorRecord $_
        }

        try {
            $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($PublishXml)
        }
        catch {
            Stop-Function -Message "Could not load profile." -ErrorRecord $_
        }

        if ($IncludeSqlCmdVars) {
            Get-SqlCmdVars -SqlCommandVariableValues $dacProfile.DeployOptions.SqlCommandVariableValues
        }

        foreach ($connstring in $ConnectionString) {
            $cleaninstance = Get-ServerName $connstring
            $instance = $cleaninstance.ToString().Replace('--', '\')

            foreach ($dbname in $database) {
                if ($GenerateDeploymentScript -or $GenerateDeploymentReport) {
                    $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
                    $DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_DeployScript_$timeStamp.sql"
                    $MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_Master.DeployScript_$timeStamp.sql"
                    $DeploymentReport = Join-Path $OutputPath "$cleaninstance-$dbname`_Result.DeploymentReport_$timeStamp.xml"
                }

                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbname"
                }

                try {
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connstring
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }

                $options = @{
                    GenerateDeploymentScript = $GenerateDeploymentScript
                    GenerateDeploymentReport = $GenerateDeploymentReport
                    DatabaseScriptPath       = $DatabaseScriptPath
                    MasterDbScriptPath       = $MasterDbScriptPath
                    DeployOptions            = $dacProfile.DeployOptions
                }

                try {
                    $global:output = @()
                    Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -Action { $global:output += $EventArgs.Message.Message } | Out-Null
                    if ($ScriptOnly) {
                        Write-Message -Level Verbose -Message "Generating script."
                        $result = $dacServices.Script($dacPackage, $dbname, $options)
                    }
                    else {
                        Write-Message -Level Verbose -Message "Executing Deployment."
                        $result = $dacServices.Publish($dacPackage, $dbname, $options)
                    }
                }
                catch [Microsoft.SqlServer.Dac.DacServicesException] {
                        Stop-Function -Message "Deployment failed" -ErrorRecord $_ -EnableException $true
                }
                finally {
                    Unregister-Event -SourceIdentifier "msg"
                    if ($GenerateDeploymentReport) {
                        $result.DeploymentReport | Out-File $DeploymentReport
                        Write-Message -Level Verbose -Message "Deployment Report - $DeploymentReport."
                    }
                    if ($GenerateDeploymentScript) {
                        Write-Message -Level Verbose -Message "Database change script - $DatabaseScriptPath."
                        if ((Test-Path $MasterDbScriptPath)) {
                            Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)."
                        }
                    }
                    $resultoutput = ($global:output -join "`r`n" | Out-String).Trim()
                    if ($resultoutput -match "Failed" -and ($GenerateDeploymentReport -or $GenerateDeploymentScript)) {
                        Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid."
                    }
                    $server = [dbainstance]$instance
                    $deployOptions = $dacProfile.DeployOptions | Select-Object -Property * -ExcludeProperty "SqlCommandVariableValues"
                    [pscustomobject]@{
                        ComputerName         = $server.ComputerName
                        InstanceName         = $server.InstanceName
                        SqlInstance          = $server.FullName
                        Database             = $dbname
                        Result               = $resultoutput
                        Dacpac               = $Path
                        PublishXml           = $PublishXml
                        ConnectionString     = $connstring
                        DatabaseScriptPath   = $DatabaseScriptPath
                        MasterDbScriptPath   = $MasterDbScriptPath
                        DeploymentReport     = $DeploymentReport
                        DeployOptions        = $deployOptions
                        SqlCmdVariableValues = $dacProfile.DeployOptions.SqlCommandVariableValues.Keys

                    } | Select-DefaultView -Property $defaultcolumns
                }
            }
        }
    }
}