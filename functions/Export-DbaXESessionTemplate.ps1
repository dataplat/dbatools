function Export-DbaXESessionTemplate {
    <#
        .SYNOPSIS
            Exports an XESession XML Template.

        .DESCRIPTION
            Exports an XESession XML Template either from the dbatools repository or a file you specify. Exports to "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" by default

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Session
            The Name of the session(s) to export.

        .PARAMETER Path
            The path to export the file into. Can be .xml or directory.

        .PARAMETER InputObject
            Specifies an XE Session output by Get-DbaXESession.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Export-DbaXESessionTemplate

        .EXAMPLE
            Export-DbaXESessionTemplate -SqlInstance sql2017 -Path C:\temp\xe

            Exports XE Session Template to the C:\temp\xe folder.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2017 -Session session_health | Export-DbaXESessionTemplate -Path C:\temp

            Returns a new XE Session object from sql2017 then adds an event, an action then creates it.

    #>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Session,
        [string]$Path = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates",
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $InputObject += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session -EnableException
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($xes in $InputObject) {
            $xesname = Remove-InvalidFileNameChars -Name $xes.Name

            if (-not (Test-Path -Path $Path)) {
                Stop-Function -Message "$Path does not exist." -Target $Path
            }

            if ($path.EndsWith(".xml")) {
                $filename = $path
            }
            else {
                $filename = "$path\$xesname.xml"
            }
            Write-Message -Level Verbose -Message "Wrote $xesname to $filename"
            [Microsoft.SqlServer.Management.XEvent.XEStore]::SaveSessionToTemplate($xes, $filename, $true)
            Get-ChildItem -Path $filename
        }
    }
}