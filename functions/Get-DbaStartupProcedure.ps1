function Get-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Get-DbaStartupProcedure gets startup procedures (user defined procedures within master database) from a SQL Server.

    .DESCRIPTION
        By default, this command returns for each SQL Server instance passed in, the SMO StoredProcedure object for all procedures in the master database that are marked as a startup procedure.
        Can be filtered to check only specific procedures

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER StartupProcedure
        Use this filter to check if specific procedure(s) are set as startup procedures.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Procedure, Startup, StartupProcedure
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance SqlBox1\Instance2

        Returns an object with all startup procedures for the Instance2 instance on SqlBox1

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure 'dbo.StartupProc'

        Returns an object with a startup procedure named 'dbo.StartupProc' for the Instance2 instance on SqlBox1

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaStartupProcedure

        Returns an object with all startup procedures for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$StartupProcedure,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $servername"

            $startupProcs = $server.EnumStartupProcedures()

            if ($startupProcs.Rows.Count -gt 0) {
                $db = $server.Databases['master']
                foreach ($startupProc in $startupProcs) {
                    if (Test-Bound -ParameterName StartupProcedure) {
                        $returnProc = $false
                        foreach ($proc in $StartupProcedure) {
                            $procParts = Get-ObjectNameParts $proc
                            if (-not $procParts.Parsed) {
                                Write-Message -Level Verbose -Message "Requested procedure $proc could not be parsed."
                                Continue
                            }
                            if (($procParts.Name -eq $startupProc.Name) -and ($procParts.Schema -eq $startupProc.Schema)) {
                                $returnProc = $true
                                Break
                            }
                        }

                    } else {
                        $returnProc = $true
                    }
                    if (!$returnProc) {
                        Continue
                    }
                    $proc = $db.StoredProcedures.Item($startupProc.Name, $startupProc.Schema)

                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                    'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                    Select-DefaultView -InputObject $proc -Property $defaults
                }
            }
        }
    }
}