function Export-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Exports an XESession XML Template using XE Session(s) output by Get-DbaXESession

    .DESCRIPTION
        Exports an XESession XML Template either from the Target SQL Server or XE Session(s) output by Get-DbaXESession. Exports to "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" by default

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        The Name of the session(s) to export.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER InputObject
        Specifies an XE Session output by Get-DbaXESession.

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
                $FilePath = "$Path\$xesname.xml"
            }
            Write-Message -Level Verbose -Message "Wrote $xesname to $FilePath"
            [Microsoft.SqlServer.Management.XEvent.XEStore]::SaveSessionToTemplate($xes, $FilePath, $true)
            Get-ChildItem -Path $FilePath
        }
    }
}