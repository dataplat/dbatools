function Publish-DbaDacPackage {
    <#
    .SYNOPSIS
        Deploys DACPAC or BACPAC files to SQL Server databases using the DacFx framework

    .DESCRIPTION
        Deploys database schema changes from DACPAC files created by SSDT projects or Export-DbaDacPackage, automatically updating target database structure and executing embedded pre/post deployment scripts. Also imports data from BACPAC files for complete database restoration scenarios. This replaces manual schema synchronization and deployment processes, making it essential for CI/CD pipelines and environment promotions. You can generate deployment scripts without applying changes for review, or use publish profiles to control deployment behavior and variable substitution.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER Path
        Specifies the filesystem path to the DACPAC or BACPAC file to deploy. The function automatically detects file type based on the extension.
        Use this to point to your compiled database project (.dacpac) or exported database backup with data (.bacpac).

    .PARAMETER PublishXml
        Specifies the path to a publish profile XML file that defines deployment options and SqlCmd variables. Created by SQL Server Data Tools (SSDT) or New-DbaDacProfile.
        Use this to control deployment behavior like dropping objects not in source, ignoring permissions, or setting variable values for different environments.

    .PARAMETER Database
        Specifies the target database name(s) to deploy the DACPAC or BACPAC to. Accepts multiple database names for deploying the same package to multiple databases.
        The database will be created if it doesn't exist, or updated to match the schema if it already exists.

    .PARAMETER ConnectionString
        Specifies the connection string to connect to the target SQL Server instance. Alternative to using SqlInstance and SqlCredential parameters.
        Use this when you need specific connection properties or when connecting through alternative authentication methods not supported by SqlInstance.

    .PARAMETER GenerateDeploymentReport
        Creates an XML deployment report showing what changes were made during the deployment. The report is saved to the OutputPath directory.
        Use this for deployment auditing, troubleshooting failed deployments, or documenting changes applied to production databases.

    .PARAMETER Type
        Specifies whether to deploy a DACPAC (schema only) or BACPAC (schema and data) file. Defaults to DACPAC.
        Use DACPAC for deploying database schema changes from development to production, or BACPAC for full database restore including data.

    .PARAMETER DacOption
        Specifies deployment options object controlling how the deployment behaves. Created using New-DbaDacOption with specific deployment settings.
        Use this to programmatically control deployment behavior instead of using a publish profile XML file, such as dropping objects not in source or ignoring permissions.

    .PARAMETER OutputPath
        Specifies the directory where deployment scripts and reports will be saved when using ScriptOnly or GenerateDeploymentReport. Defaults to the dbatools export path configuration.
        Use this to organize output files in a specific location for review, version control, or automated deployment processes.

    .PARAMETER ScriptOnly
        Generates the deployment script without executing it against the target database. The script is saved to the OutputPath directory for review.
        Use this for change approval processes, manual deployment scenarios, or to review what changes would be applied before executing them.

    .PARAMETER IncludeSqlCmdVars
        Enables replacement of SqlCmd variables in the publish profile with their actual values during deployment.
        Use this when your deployment scripts or publish profile contain variables like $(Environment) or $(ServerName) that need to be substituted with environment-specific values.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER DacFxPath
        Specifies the path to a specific version of the Microsoft.SqlServer.Dac.dll library to use for deployment operations.
        Use this when you need a specific DacFx version for compatibility with your SQL Server version or to use features from a newer DacFx release.

    .NOTES
        Tags: Deployment, Dacpac, Bacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. In 2016 the DacFx was supplied by Microsoft as a nuget package (Microsoft.Data.Tools.MSBuild) and this uses that nuget package.

    .LINK
        https://dbatools.io/Publish-DbaDacPackage

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Publish
        PS C:\> $options.DeployOptions.DropObjectsNotInSource = $true
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options -Path c:\temp\db.dacpac

        Uses DacOption object to set Deployment Options and updates DB1 database on sql2016 from the db.dacpac dacpac file, dropping objects that are missing from source.

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -Confirm

        Updates WideWorldImporters on sql2017 from the sql2016-WideWorldImporters.dacpac using the sql2016-WideWorldImporters-publish.xml publish profile. Prompts for confirmation.

    .EXAMPLE
        PS C:\> New-DbaDacProfile -SqlInstance sql2016 -Database db2 -Path C:\temp
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database db2 | Publish-DbaDacPackage -PublishXml C:\temp\sql2016-db2-publish.xml -Database db1, db2 -SqlInstance sql2017

        Creates a publish profile at C:\temp\sql2016-db2-publish.xml, exports the .dacpac to $home\Documents\sql2016-db2.dacpac. Does not prompt for confirmation.
        then publishes it to the sql2017 server database db2

    .EXAMPLE
        PS C:\> $loc = "C:\Users\bob\source\repos\Microsoft.Data.Tools.Msbuild\lib\net46\Microsoft.SqlServer.Dac.dll"
        PS C:\> Publish-DbaDacPackage -SqlInstance "local" -Database WideWorldImporters -Path C:\temp\WideWorldImporters.dacpac -PublishXml C:\temp\WideWorldImporters.publish.xml -DacFxPath $loc -Confirm

        Publishes the dacpac using a specific dacfx library. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Publish-DbaDacPackage -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml -ScriptOnly

        Does not deploy the changes, but will generate the deployment script that would be executed against WideWorldImporters.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Obj', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path,
        [Parameter(ParameterSetName = 'Xml')]
        [string]$PublishXml,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$Database,
        [string[]]$ConnectionString,
        [switch]$GenerateDeploymentReport,
        [Switch]$ScriptOnly,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [string]$OutputPath = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$IncludeSqlCmdVars,
        [Parameter(ParameterSetName = 'Obj')]
        [Alias("Option")]
        [object]$DacOption,
        [switch]$EnableException,
        [String]$DacFxPath
    )

    begin {
        if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString."
            return
        }
        if ($ConnectionString) {
            $ConnectionString = $ConnectionString | Convert-ConnectionString
        }
        if ($Type -eq 'Dacpac') {
            if ((Test-Bound -ParameterName ScriptOnly) -or (Test-Bound -ParameterName GenerateDeploymentReport)) {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions', 'SqlCmdVariableValues'
            } else {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DeployOptions', 'SqlCmdVariableValues'
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($ScriptOnly -or $GenerateDeploymentReport) {
                Stop-Function -Message "ScriptOnly and GenerateDeploymentReport cannot be used in a Bacpac scenario."
                return
            }
            $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Bacpac', 'Result', 'DeployOptions'
        }

        function Get-ServerName ($connString) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connString)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '-').Replace('(', '').Replace(')', '')
        }

        if ($DacFxPath) {
            try {
                Add-Type -Path $DacFxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded from [$DacFxPath]."
            } catch {
                Stop-Function -Message "Dac Fx could not be loaded from [$DacFxPath]." -ErrorRecord $_
                return
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path not found."
            return
        }

        # auto detect if a .bacpac was passed in, just in case the -Type param was not specified
        if (-not (Test-Bound Type) -and [IO.Path]::GetExtension($Path) -eq '.bacpac') {
            $Type = 'Bacpac'
        }

        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.PublishOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.PublishOptions object type is expected for `"-Type Dacpac`" but $($DacOption.GetType()) was passed in."
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected for `"-Type Bacpac`" but $($DacOption.GetType()) was passed in."
                return
            }
        }

        if (Test-Bound PublishXml) {
            if (-not (Test-Path -Path $PublishXml)) {
                Stop-Function -Message "$PublishXml not found."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'") | Convert-ConnectionString
        }

        #Use proper class to load the object
        if ($Type -eq 'Dacpac') {
            try {
                $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Dacpac." -ErrorRecord $_
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            try {
                $bacPackage = [Microsoft.SqlServer.Dac.BacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Bacpac." -ErrorRecord $_
                return
            }
        }
        #Load XML profile when used
        if (Test-Bound PublishXml) {
            try {
                $options = New-DbaDacOption -Type $Type -Action Publish -PublishXml $PublishXml -EnableException
            } catch {
                Stop-Function -Message "Could not load profile." -ErrorRecord $_
                return
            }
        }
        #Create/re-use deployment options object
        else {
            if (-not (Test-Bound DacOption)) {
                $options = New-DbaDacOption -Type $Type -Action Publish
            } else {
                $options = $DacOption
            }
        }
        #Replace variables if defined
        if ($IncludeSqlCmdVars) {
            Get-SqlCmdVars -SqlCommandVariableValues $options.DeployOptions.SqlCommandVariableValues
        }

        foreach ($connString in $ConnectionString) {
            $connString = $connString | Convert-ConnectionString
            $cleaninstance = Get-ServerName $connString
            $instance = $cleaninstance.ToString().Replace('--', '\')

            # Fix for #7704 to take care that $cleaninstance can be used as a filename:
            $cleaninstance = $cleaninstance.Replace(':', '_')

            foreach ($dbName in $Database) {
                #Set deployment properties when specified
                if (Test-Bound -ParameterName ScriptOnly) {
                    $options.GenerateDeploymentScript = $true
                }
                if (Test-Bound -ParameterName GenerateDeploymentReport) {
                    $options.GenerateDeploymentReport = $GenerateDeploymentReport
                }
                #Set output file paths when needed
                $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
                if ($options.GenerateDeploymentScript) {
                    if (-not $options.DatabaseScriptPath) {
                        Write-Message -Level Verbose -Message "DatabaseScriptPath not set, using default path."
                        $options.DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_DeployScript_$timeStamp.sql"
                    }
                    if (-not $options.MasterDbScriptPath) {
                        Write-Message -Level Verbose -Message "MasterDbScriptPath not set, using default path."
                        $options.MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_Master.DeployScript_$timeStamp.sql"
                    }
                }
                if ($connString -notmatch 'Database=') {
                    $connString = "$connString;Database=$dbName"
                }

                #Create services object
                try {
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connString
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }

                try {
                    $null = $output = Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -ErrorAction SilentlyContinue -Action {
                        $EventArgs.Message.Message
                    }
                    #Perform proper action depending on the Type
                    if ($Type -eq 'Dacpac') {
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Generating the deployment script as requested by the caller."
                            if (!$options.DatabaseScriptPath) {
                                Stop-Function -Message "DatabaseScriptPath option should be specified when running with -ScriptOnly" -EnableException $true
                            }
                            if ($Pscmdlet.ShouldProcess($instance, "Generating script")) {
                                $result = $dacServices.Script($dacPackage, $dbName, $options)
                            }
                        } else {
                            if ($Pscmdlet.ShouldProcess($instance, "Executing Dacpac publish")) {
                                $result = $dacServices.Publish($dacPackage, $dbName, $options)
                            }
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        if ($Pscmdlet.ShouldProcess($instance, "Executing Bacpac import")) {
                            $dacServices.ImportBacpac($bacPackage, $dbName, $options, $null)
                        }
                    }
                } catch [Microsoft.SqlServer.Dac.DacServicesException] {
                    Stop-Function -Message "Deployment failed" -ErrorRecord $_ -Continue
                } finally {
                    Unregister-Event -SourceIdentifier "msg"
                    if ($Pscmdlet.ShouldProcess($instance, "Generating deployment report and output")) {
                        if ($options.GenerateDeploymentReport) {
                            $deploymentReport = Join-Path $OutputPath "$cleaninstance-$dbName`_Result.DeploymentReport_$timeStamp.xml"
                            $result.DeploymentReport | Out-File $deploymentReport
                            Write-Message -Level Verbose -Message "Deployment Report - $deploymentReport."
                        }
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Database change script - $($options.DatabaseScriptPath)."
                            if ((Test-Path $options.MasterDbScriptPath)) {
                                Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)."
                            }
                        }
                        $resultOutput = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                        if ($resultOutput -match "Failed" -and ($options.GenerateDeploymentReport -or $options.GenerateDeploymentScript)) {
                            Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid."
                        }

                        # Fix for #7704 to take care that named pipe connections to the local host work:
                        $instance = $instance.Replace('NP:.', '.')

                        $server = [dbainstance]$instance
                        if ($Type -eq 'Dacpac') {
                            $output = [PSCustomObject]@{
                                ComputerName         = $server.ComputerName
                                InstanceName         = $server.InstanceName
                                SqlInstance          = $server.FullName
                                Database             = $dbName
                                Result               = $resultOutput
                                Dacpac               = $Path
                                PublishXml           = $PublishXml
                                ConnectionString     = $connString
                                DatabaseScriptPath   = $options.DatabaseScriptPath
                                MasterDbScriptPath   = $options.MasterDbScriptPath
                                DeploymentReport     = $DeploymentReport
                                DeployOptions        = $options.DeployOptions | Select-Object -Property * -ExcludeProperty "SqlCommandVariableValues"
                                SqlCmdVariableValues = $options.DeployOptions.SqlCommandVariableValues.Keys
                            }
                        } elseif ($Type -eq 'Bacpac') {
                            $output = [PSCustomObject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.InstanceName
                                SqlInstance      = $server.FullName
                                Database         = $dbName
                                Result           = $resultOutput
                                Bacpac           = $Path
                                ConnectionString = $connString
                                DeployOptions    = $options
                            }
                        }
                        $output | Select-DefaultView -Property $defaultColumns
                    }
                }
            }
        }
    }
}