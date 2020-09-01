function New-DbaDacProfile {
    <#
    .SYNOPSIS
        Creates a new Publish Profile.

    .DESCRIPTION
        The New-DbaDacProfile command generates a standard publish profile xml file that can be used by the DacFx (this and everything else) to control the deployment of your dacpac
        This generates a standard template XML which is enough to dpeloy a dacpac but it is highly recommended that you add additional options to the publish profile.
        If you use Visual Studio you can open a publish.xml file and use the ui to edit the file -
        To create a new file, right click on an SSDT project, choose "Publish" then "Load Profile" and load your profile or create a new one.
        Once you have loaded it in Visual Studio, clicking advanced shows you the list of options available to you.
        For a full list of options that you can add to the profile, google "sqlpackage.exe command line switches" or (https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Alternatively, you can provide a ConnectionString.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database name you are targeting

    .PARAMETER ConnectionString
        The connection string to the database you are upgrading.

        Alternatively, you can provide a SqlInstance (and optionally SqlCredential) and the script will connect and generate the connectionstring.

    .PARAMETER Path
        The directory where you would like to save the profile xml file(s).

    .PARAMETER PublishOptions
        Optional hashtable to set publish options. Key/value pairs in the hashtable get converted to strings of "<key>value</key>".

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Dacpac
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

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

        function Get-Template ($db, $connString) {
            "<?xml version=""1.0"" ?>
            <Project ToolsVersion=""14.0"" xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
              <PropertyGroup>
                <TargetDatabaseName>{0}</TargetDatabaseName>
                <TargetConnectionString>{1}</TargetConnectionString>
                <ProfileVersionNumber>1</ProfileVersionNumber>
                {2}
              </PropertyGroup>
            </Project>" -f $db[0], $connString, $(Convert-HashtableToXMLString($PublishOptions))
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace(';Application Name="dbatools PowerShell module - dbatools.io"', '')

        }

        foreach ($connString in $ConnectionString) {
            foreach ($db in $Database) {
                if ($Pscmdlet.ShouldProcess($db, "Creating new DAC Profile")) {
                    $profileTemplate = Get-Template $db, $connString
                    $instanceName = Get-ServerName $connString

                    try {
                        $server = [DbaInstance]($instanceName.ToString().Replace('--', '\'))
                        $publishProfile = Join-Path $Path "$($instanceName.Replace('--','-'))-$db-publish.xml" -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Writing to $publishProfile"
                        $profileTemplate | Out-File $publishProfile -ErrorAction Stop
                        [pscustomobject]@{
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