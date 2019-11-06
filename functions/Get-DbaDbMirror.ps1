function Get-DbaDbMirror {
    <#
    .SYNOPSIS
        Gets properties of database mirrors and mirror witnesses.

    .DESCRIPTION
        Gets properties of database mirrors and mirror witnesses.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMirror

    .EXAMPLE
        PS C:\> Get-DbaDbMirror -SqlInstance localhost

        Gets properties of database mirrors and mirror witnesses on localhost

    .EXAMPLE
        PS C:\> Get-DbaDbMirror -SqlInstance localhost, sql2016

        Gets properties of database mirrors and mirror witnesses on localhost and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $dbs = Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential
            $partners = $dbs | Where-Object MirroringPartner
            $partners | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Name, MirroringSafetyLevel, MirroringStatus, MirroringPartner, MirroringPartnerInstance, MirroringFailoverLogSequenceNumber, MirroringID, MirroringRedoQueueMaxSize, MirroringRoleSequence, MirroringSafetySequence, MirroringTimeout, MirroringWitness, MirroringWitnessStatus

            # The witness is kinda hidden. Go get it manually.
            try {
                $witnesses = $dbs[0].Parent.Query("select distinct database_name, principal_server_name, safety_level, safety_level_desc, partner_sync_state from master.sys.database_mirroring_witnesses")
            } catch { continue }

            foreach ($witness in $witnesses) {
                $witnessdb = $dbs | Where-Object Name -eq $witness.database_name
                $status = switch ($witness.partner_sync_state) {
                    0 { "None" }
                    1 { "Suspended" }
                    2 { "Disconnected" }
                    3 { "Synchronizing" }
                    4 { "PendingFailover" }
                    5 { "Synchronized" }
                }

                foreach ($db in $witnessdb) {
                    Add-Member -InputObject $db -Force -MemberType NoteProperty -Name MirroringPartner -Value $witness.principal_server_name
                    Add-Member -InputObject $db -Force -MemberType NoteProperty -Name MirroringSafetyLevel -Value $witness.safety_level_desc
                    Add-Member -InputObject $db -Force -MemberType NoteProperty -Name MirroringWitnessStatus -Value $status
                    Select-DefaultView -InputObject $db -Property ComputerName, InstanceName, SqlInstance, Name, MirroringSafetyLevel, MirroringStatus, MirroringPartner, MirroringPartnerInstance, MirroringFailoverLogSequenceNumber, MirroringID, MirroringRedoQueueMaxSize, MirroringRoleSequence, MirroringSafetySequence, MirroringTimeout, MirroringWitness, MirroringWitnessStatus
                }
            }
        }
    }
}