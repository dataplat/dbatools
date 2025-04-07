function Add-DbaReplicationLibrary {
    <#
    .SYNOPSIS
        Loads the DBA Replication replacement classes.

    .DESCRIPTION
        Loads the DBA Replication replacement classes that mimic the RMO classes but use T-SQL stored procedures.
        This is a replacement for the original Add-ReplicationLibrary function that loaded the Microsoft RMO libraries.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication, RMO
        Author: dbatools team

    .EXAMPLE
        PS C:\> Add-DbaReplicationLibrary

        Loads the DBA Replication replacement classes.
    #>
    [CmdletBinding()]
    param (
        [switch]$EnableException
    )

    try {
        # Source the DbaReplicationClasses.ps1 file to load our custom classes
        $dbaReplClassesPath = Join-DbaPath -Path $script:PSModuleRoot -ChildPath "private\functions\DbaReplicationClasses.ps1"
        . $dbaReplClassesPath

        Write-Message -Level Verbose -Message "DBA Replication replacement classes loaded successfully."
    }
    catch {
        Stop-Function -Message "Could not load DBA Replication replacement classes." -ErrorRecord $_ -EnableException $EnableException
        return
    }
}