function Get-DbaErrorLog {
    <#
    .SYNOPSIS
        Gets the "SQL Error Log" of an instance

    .DESCRIPTION
        Gets the "SQL Error Log" of an instance. Returns all 10 error logs by default.

    .PARAMETER SqlInstance
        TThe target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogNumber
        An Int32 value that specifies the index number of the error log required.
        Error logs are listed 0 through 99, where 0 is the current error log and 99 is potential oldest log file.

        SQL Server errorlog rollover defaults to 6, but can be increased to 99. https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/scm-services-configure-sql-server-error-logs

    .PARAMETER Source
        Filter results based on the Source of the error (e.g. Logon, Server, etc.)

    .PARAMETER Text
        Filter results based on a pattern of text (e.g. "login failed", "error: 12345").

    .PARAMETER After
        Filter the results based on datetime value.

    .PARAMETER Before
        Filter the results based on datetime value.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, ErrorLog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaErrorLog

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint

        Returns every log entry from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3, 6

        Returns all log entries for log number 3 and 6 on sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -Source Logon

        Returns every log entry, with a source of Logon, from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3 -Text "login failed"

        Returns every log entry for log number 3, with "login failed" in the text, from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaErrorLog -LogNumber 0

        Returns the most recent SQL Server error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -After '2016-11-14 00:00:00'

        Returns every log entry found after the date 14 November 2016 from sql101\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -Before '2016-08-16 00:00:00'

        Returns every log entry found before the date 16 August 2016 from sql101\sharepoint SQL Server instance.

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateRange(0, 99)]
        [int[]]$LogNumber,
        [object[]]$Source,
        [string]$Text,
        [datetime]$After,
        [datetime]$Before,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($LogNumber) {
                foreach ($number in $lognumber) {
                    foreach ($object in $server.ReadErrorLog($number)) {
                        if ( ($Source -and $object.ProcessInfo -ne $Source) -or ($Text -and $object.Text -notlike "*$Text*") -or ($After -and $object.LogDate -lt $After) -or ($Before -and $object.LogDate -gt $Before) ) {
                            continue
                        }
                        Write-Message -Level Verbose -Message "Processing $object"
                        Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                        # Select all of the columns you'd like to show
                        Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, 'ProcessInfo as Source', Text
                    }
                }
            } else {
                foreach ($object in $server.ReadErrorLog()) {
                    if ( ($Source -and $object.ProcessInfo -ne $Source) -or ($Text -and $object.Text -notlike "*$Text*") -or ($After -and $object.LogDate -lt $After) -or ($Before -and $object.LogDate -gt $Before) ) {
                        continue
                    }
                    Write-Message -Level Verbose -Message "Processing $object"
                    Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                    # Select all of the columns you'd like to show
                    Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, 'ProcessInfo as Source', Text
                }
            }
        }
    }
}