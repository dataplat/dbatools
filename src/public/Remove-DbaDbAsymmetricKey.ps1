function Remove-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Deletes specified asymmetric key

    .DESCRIPTION
        Deletes specified asymmetric key

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database from which the asymmetric key will be deleted.

    .PARAMETER Name
        Name of the asymmetric key to be removed

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Allows passing in of AsymmetricKey objects from Get-DbaDbAsymmetricKey

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: asymmetrickey
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbAsymmetricKey

    .EXAMPLE
        PS C:\> Remove-DbaDbAsymmetricKey -SqlInstance Server1 -Database Enctest -Name AsCert1

        The Asymmetric Key AsCert1 will be removed from the Enctest database on Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database Enctest  | Remove-DbaDbAsymmetricKey

        Will remove all the asymmetric keys found in the Enctrst databae on the Server1 instance

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$Database = "master",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AsymmetricKey[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDbAsymmetricKey -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $Name -Database $Database
        }
        foreach ($askey in $InputObject) {
            $db = $askey.Parent
            $server = $db.Parent

            if ($Pscmdlet.ShouldProcess($server.Name, "Dropping the Asymmetric key named $Name for database $db")) {
                try {
                    # erroractionprefs are not invoked for .net methods suddenly (??), so use Invoke-DbaQuery
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP ASYMMETRIC KEY $($askey.Name)" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed asymmetric key named $Name from the $db database on $server"
                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Name         = $askey.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop asymmetric key named $($askey.Name) from $($db.Name) on $($server.Name)." -Target $askey -ErrorRecord $_ -Continue
                }
            }
        }
    }
}