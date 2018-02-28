function New-DbaPublishProfile {
    <#
        .SYNOPSIS
            Creates a new Publish Profile.

        .DESCRIPTION
            The New-PublishProfile command generates a standard publish profile xml file that can be used by the DacFx (this and everything else) to control the deployment of your dacpac
            This generates a standard template XML which is enough to dpeloy a dacpac but it is highly recommended that you add additional options to the publish profile.
            If you use Visual Studio you can open a publish.xml file and use the ui to edit the file -
            To create a new file, right click on an SSDT project, choose "Publish" then "Load Profile" and load your profile or create a new one.
            Once you have loaded it in Visual Studio, clicking advanced shows you the list of options available to you.
            For a full list of options that you can add to the profile, google "sqlpackage.exe command line switches" or (https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx)

        .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to and publish to. Alternatively, you can provide a ConnectionString.

        .PARAMETER SqlCredential
        Allows you to login to servers using alternative logins instead Integrated, accepts Credential object created by Get-Credential

        .PARAMETER Database
            The database name you are targeting

        .PARAMETER ConnectionString
            The connection string to the database you are upgrading.

            Alternatively, you can provide a SqlInstance (and optionally SqlCredential) and the script will connect and generate the connectionstring.

        .PARAMETER Path
            The directory where you would like to save the profile xml file(s).

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Dacpac
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT
        .LINK
            https://dbatools.io/New-DbaPublishProfile

        .EXAMPLE
        New-DbaPublishProfile -SqlInstance sql2017 -SqlCredential (Get-Credential) -Database WorldWideImporters -Path C:\temp

        In this example, a prompt will appear for alternative credentials, tghen a connection will be made to sql2017. Using that connection,
        the ConnectionString will be extracted and used within the Publish Profile XML file which will be created at C:\temp\sql2017-WorldWideImporters-publish.xml

        .EXAMPLE
        New-DbaPublishProfile -Database WorldWideImporters -Path C:\temp -ConnectionString "SERVER=(localdb)\MSSQLLocalDB;Integrated Security=True;Database=master"

        In this example, no connections are made, and a Publish Profile XML would be created at C:\temp\localdb-MSSQLLocalDB-WorldWideImporters-publish.xml
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [string[]]$Database,
        [string]$Path = "$home\Documents",
        [string[]]$ConnectionString,
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

        function Get-Template ($db, $connstring) {
            "<?xml version=""1.0"" ?>
            <Project ToolsVersion=""14.0"" xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
              <PropertyGroup>
                <TargetDatabaseName>{0}</TargetDatabaseName>
                <TargetConnectionString>{1}</TargetConnectionString>
                <ProfileVersionNumber>1</ProfileVersionNumber>
              </PropertyGroup>
            </Project>" -f $db[0], $connstring
        }

        function Get-ServerName ($connstring) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connstring)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '--')
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace(';Application Name="dbatools PowerShell module - dbatools.io"', '')

        }

        foreach ($connstring in $ConnectionString) {
            foreach ($db in $Database) {
                $profileTemplate = Get-Template $db, $connstring
                $instancename = Get-ServerName $connstring

                try {
                    $server = [DbaInstance]($instancename.ToString().Replace('--', '\'))
                    $PublishProfile = Join-Path $Path "$($instancename.Replace('--','-'))-$db-publish.xml" -ErrorAction Stop
                    Write-Message -Level Verbose -Message "Writing to $PublishProfile"
                    $profileTemplate | Out-File $PublishProfile -ErrorAction Stop
                    [pscustomobject]@{
                        ComputerName     = $server.ComputerName
                        InstanceName     = $server.InstanceName
                        SqlInstance      = $server.FullName
                        Database         = $db
                        FileName         = $PublishProfile
                        ConnectionString = $connstring
                        ProfileTemplate  = $profileTemplate
                    } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ProfileTemplate
                }
                catch {
                    Stop-Function -ErrorRecord $_ -Message "Failure" -Target $instancename -Continue
                }
            }
        }
    }
}