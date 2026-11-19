function New-DbaDacProfile {
    <#
    .SYNOPSIS
        Creates DAC publish profile XML files for automated dacpac deployment to SQL Server databases.

    .DESCRIPTION
        The New-DbaDacProfile command generates standard publish profile XML files that control how DacFx deploys your dacpac files to SQL Server databases. These profile files define deployment settings like target database, connection details, and deployment options.

        The generated XML template includes basic deployment settings sufficient for most dacpac deployments, but you'll typically want to add additional deployment options to the publish profile for production scenarios.

        If you use Visual Studio with SSDT projects, you can enhance these profiles through the UI. Right-click on an SSDT project, choose "Publish", then "Load Profile" to load your generated profile. The Advanced button reveals the full list of available deployment options.

        For automation scenarios, these profiles work directly with SqlPackage.exe command-line deployments, eliminating the need to specify connection and deployment settings manually each time.

        For a complete list of deployment options you can add to profiles, search for "SqlPackage.exe command line switches" or visit https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Alternatively, you can provide a ConnectionString.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database name where the dacpac will be deployed. This sets the TargetDatabaseName property in the generated publish profile.
        Use this to define which database will receive the dacpac deployment when the profile is used with SqlPackage.exe or Visual Studio publishing.

    .PARAMETER ConnectionString
        Provides a direct connection string for the target SQL Server instance and database. This becomes the TargetConnectionString in the generated publish profile.
        Use this instead of SqlInstance when you need specific connection parameters, are connecting to non-standard instances like LocalDB, or when working in environments where Connect-DbaInstance may have limitations.
        If you provide SqlInstance, the function will connect and generate the connection string automatically.

    .PARAMETER Path
        Specifies the directory where the publish profile XML files will be created. Defaults to your Documents folder if not specified.
        Files are automatically named using the pattern "instancename-databasename-publish.xml" for easy identification and organization.

    .PARAMETER PublishOptions
        Specifies additional deployment options as a hashtable that will be embedded in the publish profile XML. Each key/value pair becomes a PropertyGroup element in the profile.
        Use this to control dacpac deployment behavior like blocking data loss (BlockOnPossibleDataLoss), ignoring permissions (IgnorePermissions), or script generation options.
        Common options include IgnoreUserSettingsObjects, GenerateDeploymentScript, and CreateNewDatabase. See SqlPackage.exe documentation for complete option list.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Dacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        .OUTPUTS
        PSCustomObject

        Returns one result object per database specified when generating a publish profile. Objects combine connection context and profile metadata.

        Properties:
        - ComputerName: Computer name extracted from the DbaInstance object (derived from connection string)
        - InstanceName: Instance name extracted from the DbaInstance object (derived from connection string)
        - SqlInstance: Full SQL Server instance name in format "ComputerName\InstanceName" (from DbaInstance.FullName)
        - Database: Target database name for which the profile was generated
        - FileName: Full file path to the generated XML publish profile (e.g., "C:\temp\sql2017-WorldWideImporters-publish.xml")
        - ConnectionString: The connection string embedded in the profile (e.g., "Server=sql2017;Integrated Security=True;Encrypt=False")
        - ProfileTemplate: Complete XML content of the publish profile (excluded from default display via Select-DefaultView)

        Default display properties (via Select-DefaultView):
        - SqlInstance: SQL Server instance name
        - Database: Target database
        - FileName: Profile file path
        - ConnectionString: Connection string

        Output Quantity:
        Returns one object per database specified in the -Database parameter for each connection string. For example:
        - Specifying one database with one connection string returns 1 object
        - Specifying multiple databases (DB1, DB2) with one connection string returns 2 objects
        - Specifying multiple databases with multiple connection strings returns (databases count × connection strings count) objects

        The ProfileTemplate property contains the XML used for SqlPackage.exe deployments. This property is excluded from default display but accessible via Select-Object or property access.
    .LINK
        https://dbatools.io/New-DbaDacProfile

    .EXAMPLE
        PS C:\> New-DbaDacProfile -SqlInstance sql2017 -SqlCredential ad\sqldba -Database WorldWideImporters -Path C:\temp

        In this example, a prompt will appear for alternative credentials, then a connection will be made to sql2017. Using that connection,
        the ConnectionString will be extracted and used within the Publish Profile XML file which will be created at C:\temp\sql2017-WorldWideImporters-publish.xml

    .EXAMPLE
        PS C:\> New-DbaDacProfile -Database WorldWideImporters -Path C:\temp -ConnectionString "SERVER=(localdb)\MSSQLLocalDB;Integrated Security=True;Database=master"

        In this example, no connections are made, and a Publish Profile XML would be created at C:\temp\localdb-MSSQLLocalDB-WorldWideImporters-publish.xml

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [string[]]$Database,
        [string]$Path = "$home\Documents",
        [string[]]$ConnectionString,
        [hashtable]$PublishOptions,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString"
        }

        if (-not (Test-Path $Path)) {
            Stop-Function -Message "$Path doesn't exist or access denied"
        }

        if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
            Stop-Function -Message "Path must be a directory"
        }

        function Convert-HashtableToXMLString($PublishOptions) {
            $return = @()
            if ($PublishOptions) {
                $PublishOptions.GetEnumerator() | ForEach-Object {
                    $key = $PSItem.Key.ToString()
                    $value = $PSItem.Value.ToString()
                    $return += "<$key>$value</$key>"
                }
            }
            $return | Out-String
        }

        function Get-Template {
            param (
                $db,
                $connString
            )

            "<?xml version=""1.0"" ?>
            <Project ToolsVersion=""14.0"" xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
              <PropertyGroup>
                <TargetDatabaseName>{0}</TargetDatabaseName>
                <TargetConnectionString>{1}</TargetConnectionString>
                <ProfileVersionNumber>1</ProfileVersionNumber>
                {2}
              </PropertyGroup>
            </Project>" -f $db, $connString, $(Convert-HashtableToXMLString($PublishOptions))
        }

        function Get-ServerName ($connString) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connString)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            $instance = $instance.ToString().Replace('TCP:', '')
            $instance = $instance.ToString().Replace('tcp:', '')
            return $instance.ToString().Replace('\', '--')
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace(';Application Name="dbatools PowerShell module - dbatools.io"', '').Replace(";Encrypt=False", "").Replace(";Trust Server Certificate=False", "") | Convert-ConnectionString

        }

        foreach ($connString in $ConnectionString) {
            foreach ($db in $Database) {
                if ($Pscmdlet.ShouldProcess($db, "Creating new DAC Profile")) {
                    $profileTemplate = Get-Template -db $db -connString $connString
                    $instanceName = Get-ServerName $connString

                    try {
                        $server = [DbaInstance]($instanceName.ToString().Replace('--', '\'))
                        $publishProfile = Join-Path $Path "$($instanceName.Replace('--','-'))-$db-publish.xml" -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Writing to $publishProfile"
                        $profileTemplate | Out-File $publishProfile -ErrorAction Stop
                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.InstanceName
                            SqlInstance      = $server.FullName
                            Database         = $db
                            FileName         = $publishProfile
                            ConnectionString = $connString
                            ProfileTemplate  = $profileTemplate
                        } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ProfileTemplate
                    } catch {
                        Stop-Function -ErrorRecord $_ -Message "Failure" -Target $instanceName -Continue
                    }
                }
            }
        }
    }
}
