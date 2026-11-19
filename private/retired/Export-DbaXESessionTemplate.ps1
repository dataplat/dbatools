function Export-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Exports Extended Events sessions as reusable XML templates for SSMS

    .DESCRIPTION
        Converts existing Extended Events sessions into XML template files that can be imported and reused in SQL Server Management Studio.
        This lets you standardize XE session configurations across multiple environments without manually recreating session definitions.
        Templates are saved to the SSMS XEvent templates folder by default, making them immediately available in the SSMS template browser.
        Accepts sessions directly from SQL Server instances or from Get-DbaXESession pipeline output.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Specifies which Extended Events sessions to export by name. Accepts wildcards for pattern matching.
        Use this to export specific sessions instead of all sessions on the instance. Common sessions include system_health, AlwaysOn_health, or custom monitoring sessions.

    .PARAMETER Path
        Sets the directory where XML template files will be saved. Defaults to the SSMS XEvent Templates folder in your Documents.
        Templates saved to the default location appear automatically in SSMS under Templates > XEventTemplates for easy reuse.

    .PARAMETER FilePath
        Sets the complete file path including filename for the exported template. Use when you need a specific filename or location.
        When specified, only one session can be exported at a time. If not provided, files are named after the session and saved to the Path directory.

    .PARAMETER InputObject
        Accepts Extended Events session objects from Get-DbaXESession pipeline input.
        Use this when you need to filter sessions first or when working with sessions from multiple instances in a single export operation.

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
        https://dbatools.io/Export-DbaXESessionTemplate

    .OUTPUTS
        System.IO.FileInfo

        Returns one FileInfo object per Extended Events session exported. Each object represents the XML template file that was created.

        Properties:
        - Name: The filename of the exported XE session template (e.g., "system_health.xml")
        - FullName: The complete path to the exported template file
        - DirectoryName: The directory path where the template file was saved
        - Extension: The file extension (".xml")
        - Length: The size of the template file in bytes
        - CreationTime: When the template file was created
        - LastWriteTime: When the template file was last modified
        - LastAccessTime: When the template file was last accessed
        - Mode: File attributes and permissions (e.g., "-a----")

    .EXAMPLE
        PS C:\> Export-DbaXESessionTemplate -SqlInstance sql2017 -Path C:\temp\xe

        Exports an XESession XML Template for all Extended Event Sessions on sql2017 to the C:\temp\xe folder.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2017 -Session system_health | Export-DbaXESessionTemplate -Path C:\temp\xe

        Gets the system_health Extended Events Session from sql2017 and then exports as an XESession XML Template to C:\temp\xe

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Session,
        # intentionally left because this is where SSMS defaults
        [string]$Path = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates",
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $InputObject += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session -EnableException
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($xes in $InputObject) {
            $xesname = Remove-InvalidFileNameChars -Name $xes.Name

            if (-not (Test-Path -Path $Path)) {
                Stop-Function -Message "$Path does not exist." -Target $Path
            }

            if (-not $PSBoundParameters.FilePath) {
                $FilePath = Join-DbaPath $Path "$xesname.xml"
            }
            Write-Message -Level Verbose -Message "Wrote $xesname to $FilePath"
            [Microsoft.SqlServer.Management.XEvent.XEStore]::SaveSessionToTemplate($xes, $FilePath, $true)
            Get-ChildItem -Path $FilePath
        }
    }
}