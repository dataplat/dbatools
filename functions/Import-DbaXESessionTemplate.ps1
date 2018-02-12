function Import-DbaXESessionTemplate {
    <#
        .SYNOPSIS
            Imports a new XESession XML Template

        .DESCRIPTION
            Imports a new XESession XML Template either from the dbatools repository or a file you specify.

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Name
            The Name of the session to create.

        .PARAMETER Path
            The path to the xml file or files for the session(s).

        .PARAMETER Template
            Specifies the name of one of the templates from the dbatools repository. Press tab to cycle through the provided templates.

        .PARAMETER TargetFilePath
            By default, files will be created in the default xel directory. Use TargetFilePath to change all instances of
            filename = "file.xel" to filename = "$TargetFilePath\file.xel". Only specify the directory, not the file itself.

            This path is relative to the destination directory
    
        .PARAMETER TargetFileMetadataPath
            By default, files will be created in the default xem directory. Use TargetFileMetadataPath to change all instances of
            filename = "file.xem" to filename = "$TargetFilePath\file.xem". Only specify the directory, not the file itself.

            This path is relative to the destination directory

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Import-DbaXESessionTemplate

        .EXAMPLE
            Import-DbaXESessionTemplate -SqlInstance sql2017 -Template db_query_wait_stats

            Creates a new XESession named db_query_wait_stats from the dbatools repository to the SQL Server sql2017.

        .EXAMPLE
            Import-DbaXESessionTemplate -SqlInstance sql2017 -Template db_query_wait_stats -Name "Query Wait Stats"

            Creates a new XESession named "Query Wait Stats" using the db_query_wait_stats template.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2017 -Session db_ola_health | Remove-DbaXESession
            Import-DbaXESessionTemplate -SqlInstance sql2017 -Template db_ola_health | Start-DbaXESession

            Imports a session if it exists, then recreates it using a template.

        .EXAMPLE
            Get-DbaXESessionTemplate | Out-GridView -PassThru | Import-DbaXESessionTemplate -SqlInstance sql2017

            Allows you to select a Session template then import to an instance named sql2017.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string[]]$Template,
        [string]$TargetFilePath,
        [string]$TargetFileMetadataPath,
        [switch]$EnableException
    )
    begin {
        $metadata = Import-Clixml "$script:PSModuleRoot\bin\xetemplates-metadata.xml"
    }
    process {
        if ((Test-Bound -ParameterName Path -Not) -and (Test-Bound -ParameterName Template -Not)) {
            Stop-Function -Message "You must specify Path or Template."
        }

        if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and (Test-Bound -ParameterName Template)) {
            Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist."
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

            foreach ($file in $template) {
                $templatepath = "$script:PSModuleRoot\bin\xetemplates\$file.xml"
                if ((Test-Path $templatepath)) {
                    $Path += $templatepath
                }
                else {
                    Stop-Function -Message "Invalid template ($templatepath does not exist)." -Continue
                }
            }

            foreach ($file in $Path) {

                if ((Test-Bound -Not -ParameterName TargetFilePath)) {
                    Write-Message -Level Verbose -Message "Importing $file to $instance"
                    try {
                        $xml = [xml](Get-Content $file -ErrorAction Stop)
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }
                }
                else {
                    Write-Message -Level Verbose -Message "TargetFilePath specified, changing all file locations in $file for $instance."
                    Write-Message -Level Verbose -Message "TargetFileMetadataPath specified, changing all metadata file locations in $file for $instance."
                    
                    # Handle whatever people specify
                    $TargetFilePath = $TargetFilePath.TrimEnd("\")
                    $TargetFileMetadataPath = $TargetFileMetadataPath.TrimEnd("\")
                    $TargetFilePath = "$TargetFilePath\"
                    $TargetFileMetadataPath = "$TargetFileMetadataPath\"
                    
                    # Perform replace
                    $xelphrase = 'name="filename" value="'
                    $xemphrase = 'name="metadatafile" value="'
                    
                    try {
                        $basename = (Get-ChildItem $file).Basename
                        $contents = Get-Content $file -ErrorAction Stop
                        $contents = $contents.Replace($xelphrase, "$xelphrase$TargetFilePath")
                        $contents = $contents.Replace($xemphrase, "$xemphrase$TargetFileMetadataPath")
                        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\")
                        $tempfile = "$temp\$basename"
                        $null = Set-Content -Path $tempfile -Value $contents -Encoding UTF8
                        $xml = [xml](Get-Content $tempfile -ErrorAction Stop)
                        $file = $tempfile
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }

                    Write-Message -Level Verbose -Message "$TargetFilePath does not exist on $server, creating now."
                    try {
                        if (-not (Test-DbaSqlPath -SqlInstance $server -Path $TargetFilePath)) {
                            $null = New-DbaSqlDirectory -SqlInstance $server -Path $TargetFilePath
                        }
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }
                }

                if (-not $xml.event_sessions) {
                    Stop-Function -Message "$file is not a valid XESession template document." -Continue
                }

                if ((Test-Bound -ParameterName Name -not)) {
                    $Name = (Get-ChildItem $file).BaseName
                }
                
                # This could be done better but not today
                $no2012 = ($metadata | Where-Object Compatibility -gt 2012).Name
                $no2014 = ($metadata | Where-Object Compatibility -gt 2014).Name

                if ($Name -in $no2012 -and $server.VersionMajor -eq 11) {
                    Stop-Function -Message "$Name is not supported in SQL Server 2012 ($server)" -Continue
                }
                
                if ($Name -in $no2014 -and $server.VersionMajor -eq 12) {
                    Stop-Function -Message "$Name is not supported in SQL Server 2014 ($server)" -Continue
                }
                
                if ((Get-DbaXESession -SqlInstance $server -Session $Name)) {
                    Stop-Function -Message "$Name already exists on $instance" -Continue
                }

                try {
                    Write-Message -Level Verbose -Message "Importing $file as $name "
                    $session = $store.CreateSessionFromTemplate($Name, $file)
                    $session.Create()
                    if ($file -eq $tempfile) {
                        Remove-Item $tempfile -ErrorAction SilentlyContinue
                    }
                    Get-DbaXESession -SqlInstance $server -Session $session.Name
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                }
            }
        }
    }
}