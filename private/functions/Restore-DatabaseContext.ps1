function Restore-DatabaseContext {
    <#
    .SYNOPSIS
        Puts the current database of a connection back where the caller had it.

    .DESCRIPTION
        Database scoped SMO work moves the current database of the connection and never moves it back:
        the execution manager of a Database object is the connection context of the parent server, which
        belongs to the caller, and SMO issues a USE on it. That happens for ExecuteNonQuery and
        ExecuteWithResults on a Database object, for Create and Drop of most server level objects, and for
        enumerating any database level collection such as Views, Tables or Users. See #10555.

        A command that cannot avoid moving the context calls this to put it back. Read
        ConnectionContext.CurrentDatabase before the command starts its work, so the value is the database
        the caller was in and not one that a statement of the command left behind, and call this from a
        finally so a failing statement still puts the database back.

        Putting the database back is housekeeping and must never become the outcome of the command, so a
        failing restore warns instead of throwing. A query that makes the previous database unreachable -
        taking it offline, dropping it, renaming it, revoking access - would otherwise report a failure
        although the command succeeded.

    .PARAMETER Server
        The server object whose connection was moved. This is the object the caller passed in or that the
        command connected with, not a copy.

    .PARAMETER Database
        The name of the database to go back to, read from ConnectionContext.CurrentDatabase before the work
        started. Nothing happens when it is empty, so a command may pass a value it never managed to read.

    .NOTES
        Tags: Connection, Database
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        None. The current database of the connection is changed as a side effect.

    .EXAMPLE
        PS C:\> $callerDatabase = $server.ConnectionContext.CurrentDatabase
        PS C:\> try {
        PS C:\>     $views = $db.Views
        PS C:\> } finally {
        PS C:\>     Restore-DatabaseContext -Server $server -Database $callerDatabase
        PS C:\> }

        Enumerating the views leaves the connection in that database. This puts the database of the caller
        back, whatever the enumeration did.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Server]$Server,
        [string]$Database
    )

    if (-not $Database) {
        return
    }

    # The comparison is case sensitive on purpose. Database names use the collation of the instance, so on
    # a case sensitive instance AppDb and appdb are two different databases, and -eq would report them as
    # equal and skip the restore. It cannot restore needlessly: both sides are read from the same property,
    # so the same database always spells itself the same way.
    if ($Server.ConnectionContext.CurrentDatabase -ceq $Database) {
        return
    }

    $escapedDatabase = $Database.Replace("]", "]]")

    try {
        $null = $Server.ConnectionContext.ExecuteNonQuery("USE [$escapedDatabase]")
    } catch {
        Write-Message -Level Warning -Message "The database context could not be restored to [$Database]: $_"
    }
}
