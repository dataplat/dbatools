function Get-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Gets database Asymmetric Key

    .DESCRIPTION
        Gets database Asymmetric Key

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Get Asymmetric Keys from specific database

    .PARAMETER ExcludeDatabase
        Database(s) to ignore when retrieving Asymmetric Keys

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER Name
        Get specific Asymmetric Key by name

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AsymmetricKey
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbAsymmetricKey

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance sql2016

        Gets all Asymmetric Keys

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1

        Gets the Asymmetric Keys for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Name key1

        Gets the key1 Asymmetric Key within the db1 database

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "$db is not accessible, skipping"
                continue
            }

            $akeys = $db.AsymmetricKeys

            if ($null -eq $akeys) {
                Write-Message -Message "No Asymmetic Keys exists in the $db database on $instance" -Target $db -Level Verbose
                continue
            }

            if ($Name) {
                $akeys = $akeys | Where-Object Name -in $Name
            }

            foreach ($akey in $akeys) {
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name ComputerName -value $db.ComputerName
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name InstanceName -value $db.InstanceName
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name SqlInstance -value $db.SqlInstance
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name Database -value $db.Name

                Select-DefaultView -InputObject $akey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, KeyEncryptionAlgorithm, KeyLength, PrivateKeyEncryptionType, Thumbprint
            }
        }
    }
}