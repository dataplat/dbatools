function Remove-DbaReplArticle {
    <#
    .SYNOPSIS
        Removes articles from SQL Server replication publications and their associated subscriptions.

    .DESCRIPTION
        Removes articles from SQL Server replication publications, automatically handling subscription cleanup when subscribers exist. This function is essential when you need to stop replicating specific tables, views, or stored procedures without dismantling the entire publication.

        When articles have active subscriptions, the function first removes them from all subscribers using sp_dropsubscription before removing the article from the publication itself. This prevents orphaned subscription entries that could cause synchronization issues.

        Important considerations: Dropping an article from a publication does not remove the actual object from the publication database or the corresponding object from the subscription database. Use DROP <Object> statements to remove these objects if necessary. Additionally, dropping an article invalidates the current snapshot, so a new snapshot must be created before the next synchronization cycle.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the publication database on the publisher that contains the article to remove from replication.
        This is the database where the source objects (tables, views, stored procedures) exist and are published for replication.

    .PARAMETER Publication
        Specifies the name of the replication publication from which to remove the article.
        Use Get-DbaReplPublication to list available publications if you're unsure of the exact name.

    .PARAMETER Schema
        Specifies the schema name of the replicated object to remove from the publication. Defaults to 'dbo'.
        Required when multiple schemas contain objects with the same name, ensuring you remove the correct article.

    .PARAMETER Name
        Specifies the name of the article to remove from the publication.
        This corresponds to the source object name (table, view, or stored procedure) that was added to replication.

    .PARAMETER DropObjectOnSubscriber
        If this switch is enabled, the object will be dropped from the subscriber database.

    .PARAMETER InputObject
        Accepts replication article objects from Get-DbaReplArticle for pipeline operations.
        Use this to remove multiple articles efficiently: Get-DbaReplArticle | Remove-DbaReplArticle.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/delete-an-article

    .OUTPUTS
        PSCustomObject

        Returns one object per article removed from the replication publication.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The publication database name
        - ObjectName: The name of the replicated object (table, view, or stored procedure)
        - ObjectSchema: The schema that owns the replicated object
        - Status: "Removed" on successful removal, or an error message if the operation failed
        - IsRemoved: Boolean indicating whether the article was successfully removed (true) or failed (false)

    .LINK
        https://dbatools.io/Remove-DbaReplArticle

    .EXAMPLE
        PS C:\> Remove-DbaReplArticle -SqlInstance mssql1 -Database Pubs -Publication PubFromPosh -Name 'publishers'

        Removes the publishers article from a publication called PubFromPosh on mssql1

    .EXAMPLE

        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database Pubs -Publication TestPub | Remove-DbaReplArticle

        Removes all articles from a publication called TestPub on mssql1
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String]$Database,
        [String]$Publication,
        [String]$Schema = 'dbo',
        [String]$Name,
        #[Switch]$DropObjectOnSubscriber,
        [Parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [Switch]$EnableException
    )

    begin {
        Add-ReplicationLibrary
        $articles = @( )
    }

    process {
        if (-not $PSBoundParameters.SqlInstance -and -not $PSBoundParameters.InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or InputObject"
            return
        }

        if ($InputObject) {
            $articles += $InputObject
        } else {
            $params = $PSBoundParameters
            $null = $params.Remove('InputObject')
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $articles = Get-DbaReplArticle @params
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaReplArticle.
        foreach ($art in $articles) {
            if ($PSCmdlet.ShouldProcess($art.Name, "Removing the article $($art.SourceObjectOwner).$($art.SourceObjectName) from the $($art.PublicationName) publication on $($art.SqlInstance)")) {
                $output = [pscustomobject]@{
                    ComputerName = $art.ComputerName
                    InstanceName = $art.InstanceName
                    SqlInstance  = $art.SqlInstance
                    Database     = $art.DatabaseName
                    ObjectName   = $art.SourceObjectName
                    ObjectSchema = $art.SourceObjectOwner
                    Status       = $null
                    IsRemoved    = $false
                }
                try {

                    $pub = Get-DbaReplPublication -SqlInstance $art.SqlInstance -SqlCredential $SqlCredential -Database $art.DatabaseName -Name $art.PublicationName -EnableException:$EnableException

                    if (($pub.Subscriptions | Measure-Object).count -gt 0 ) {
                        Write-Message -Level Verbose -Message ("There is a subscription so remove article {0} from subscription on {1}" -f $art.Name, $pub.Subscriptions.SubscriberName)
                        $query = "EXEC sp_dropsubscription @publication = '{0}', @article= '{1}',@subscriber = '{2}'" -f $art.PublicationName, $art.Name, $pub.Subscriptions.SubscriberName
                        Invoke-DbaQuery -SqlInstance $art.SqlInstance -SqlCredential $SqlCredential -Database $art.DatabaseName -query $query -EnableException:$EnableException
                    }
                    if (($art.IsExistingObject)) {
                        $art.Remove()
                    } else {
                        Stop-Function -Message "Article doesn't exist in $PublicationName on $instance" -Target $instance -Continue
                    }
                    $output.Status = "Removed"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed to remove the article from publication" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}