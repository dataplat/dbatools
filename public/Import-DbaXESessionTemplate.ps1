function Import-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Creates Extended Events sessions from XML templates on SQL Server instances

    .DESCRIPTION
        Creates new Extended Events sessions using predefined XML templates from the dbatools repository or custom template files you specify. This function simplifies XE session deployment by providing ready-to-use templates for common monitoring scenarios like performance troubleshooting, security auditing, and health monitoring.

        Templates from the dbatools repository include popular configurations for index page splits, query wait statistics, deadlock monitoring, IO errors, and database health checks. You can also import custom templates created from existing sessions or third-party sources.

        The function automatically handles SQL Server version compatibility, validates template XML structure, checks for existing sessions to prevent conflicts, and can optionally start sessions immediately with auto-start configuration for server restarts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies a custom name for the Extended Events session being created. When not provided, the session name defaults to the template filename.
        Use this when you need multiple sessions from the same template or want descriptive names that match your monitoring standards.

    .PARAMETER Path
        Specifies the full file path to custom Extended Events session XML template files. Accepts multiple file paths for bulk imports.
        Use this when importing custom templates you've created or third-party XE session definitions instead of built-in dbatools templates.

    .PARAMETER Template
        Specifies the name of a built-in Extended Events template from the dbatools repository. Accepts multiple template names for bulk deployment.
        Use tab completion to browse available templates like "Blocked Process Report", "Query Wait Statistics", or "Index Page Splits". These templates provide pre-configured monitoring for common DBA scenarios.

    .PARAMETER TargetFilePath
        Overrides the default directory for Extended Events trace files (.xel files) in the template. Specify only the directory path, not filenames.
        Use this when you need XE files stored in specific locations for storage management, compliance, or performance reasons. The path is relative to the SQL Server instance.

    .PARAMETER TargetFileMetadataPath
        Overrides the default directory for Extended Events metadata files (.xem files) in the template. Specify only the directory path, not filenames.
        Use this when you need XE metadata files stored separately from trace files or in specific locations for organizational purposes. The path is relative to the SQL Server instance.

    .PARAMETER StartUpState
        Controls whether the Extended Events session starts immediately and automatically restarts after SQL Server restarts. Default is Off.
        Set to "On" when you need continuous monitoring that survives server restarts, such as for production performance monitoring or security auditing sessions.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Import-DbaXESessionTemplate

    .EXAMPLE
        PS C:\> Import-DbaXESessionTemplate -SqlInstance sql2017 -Template "15 Second IO Error"

        Creates a new XESession named "15 Second IO Error" from the dbatools repository to the SQL Server sql2017.

    .EXAMPLE
        PS C:\> Import-DbaXESessionTemplate -SqlInstance sql2017 -Template "Index Page Splits" -StartUpState On

        Creates a new XESession named "Index Page Splits" from the dbatools repository to the SQL Server sql2017, starts the XESession and sets the StartUpState to On so that it starts on the next server restart.

    .EXAMPLE
        PS C:\> Import-DbaXESessionTemplate -SqlInstance sql2017 -Template "Query Wait Statistics" -Name "Query Wait Stats" | Start-DbaXESession

        Creates a new XESession named "Query Wait Stats" using the Query Wait Statistics template, then immediately starts it.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2017 -Session 'Database Health 2014' | Remove-DbaXESession
        PS C:\> Import-DbaXESessionTemplate -SqlInstance sql2017 -Template 'Database Health 2014' | Start-DbaXESession

        Removes a session if it exists, then recreates it using a template.

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate | Out-GridView -PassThru | Import-DbaXESessionTemplate -SqlInstance sql2017

        Allows you to select a Session template then import to an instance named sql2017.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string[]]$Template,
        [string]$TargetFilePath,
        [string]$TargetFileMetadataPath,
        [ValidateSet("On", "Off")]
        [string]$StartUpState = "Off",
        [switch]$EnableException
    )
    begin {
        $xmlpath = Join-DbaPath $script:PSModuleRoot "bin" "xetemplates-metadata.xml"
        $metadata = Import-Clixml $xmlpath
    }
    process {
        if ((Test-Bound -ParameterName Path -Not) -and (Test-Bound -ParameterName Template -Not)) {
            Stop-Function -Message "You must specify Path or Template."
        }

        if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and (Test-Bound -ParameterName Name)) {
            Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $store = New-Object Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

            foreach ($file in $template) {
                $templatepath = Join-DbaPath $script:PSModuleRoot "bin" "XEtemplates" "$file.xml"
                if ((Test-Path $templatepath)) {
                    $Path += $templatepath
                } else {
                    Stop-Function -Message "Invalid template ($templatepath does not exist)." -Continue
                }
            }

            foreach ($file in $Path) {

                if ((Test-Bound -Not -ParameterName TargetFilePath)) {
                    Write-Message -Level Verbose -Message "Importing $file to $instance"
                    try {
                        $xml = [xml](Get-Content $file -ErrorAction Stop)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }
                } else {
                    Write-Message -Level Verbose -Message "TargetFilePath specified, changing all file locations in $file for $instance."
                    Write-Message -Level Verbose -Message "TargetFileMetadataPath specified, changing all metadata file locations in $file for $instance."

                    # Handle whatever people specify
                    $TargetFilePath = $TargetFilePath.TrimEnd("\").TrimEnd("/")
                    $TargetFileMetadataPath = $TargetFileMetadataPath.TrimEnd("\").TrimEnd("/")
                    if ((Test-HostOSLinux -SqlInstance $server)) {
                        $TargetFilePath = "$TargetFilePath/".$file.TrimEnd("\").TrimEnd("/")
                        $TargetFileMetadataPath = "$TargetFileMetadataPath/"
                    } else {
                        $TargetFilePath = "$TargetFilePath\"
                        $TargetFileMetadataPath = "$TargetFileMetadataPath\"
                    }

                    # Perform replace
                    $xelphrase = 'name="filename" value="'
                    $xemphrase = 'name="metadatafile" value="'

                    try {
                        $basename = (Get-ChildItem $file).Basename
                        $contents = Get-Content $file -ErrorAction Stop
                        $contents = $contents.Replace($xelphrase, "$xelphrase$TargetFilePath")
                        $contents = $contents.Replace($xemphrase, "$xemphrase$TargetFileMetadataPath")
                        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\").TrimEnd("/")
                        $tempfile = Join-DbaPath $temp $basename
                        $null = Set-Content -Path $tempfile -Value $contents -Encoding UTF8
                        $xml = [xml](Get-Content $tempfile -ErrorAction Stop)
                        $file = $tempfile
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                    }

                    Write-Message -Level Verbose -Message "$TargetFilePath does not exist on $server, creating now."
                    try {
                        if (-not (Test-DbaPath -SqlInstance $server -Path $TargetFilePath).FileExists) {
                            $null = New-DbaDirectory -SqlInstance $server -Path $TargetFilePath
                        }
                    } catch {
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
                    Write-Message -Level Verbose -Message "Importing $file as $Name"
                    $session = $store.CreateSessionFromTemplate($Name, $file)
                    $session.Create()
                    if ($file -eq $tempfile) {
                        Remove-Item $tempfile -ErrorAction SilentlyContinue
                    }
                    if ($StartUpState -eq "On") {
                        $newsession = Get-DbaXESession -SqlInstance $server -Session $session.Name
                        if (-not $newsession.AutoStart) {
                            $newsession.AutoStart = $true
                            $newsession.Alter()
                        }
                        $newsession | Start-DbaXESession
                    } else {
                        Get-DbaXESession -SqlInstance $server -Session $session.Name
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                }
            }
        }
    }
}