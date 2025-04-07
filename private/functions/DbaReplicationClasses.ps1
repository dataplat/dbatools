# Replacement classes for Microsoft.SqlServer.Replication namespace
# These classes mimic the RMO classes but use T-SQL stored procedures instead

# Base class for replication objects
class DbaReplObject {
    [string]$ComputerName
    [string]$InstanceName
    [string]$SqlInstance
    [System.Data.SqlClient.SqlConnection]$ConnectionContext

    DbaReplObject() {
        # Default constructor
    }

    DbaReplObject([System.Data.SqlClient.SqlConnection]$ConnectionContext) {
        $this.ConnectionContext = $ConnectionContext
    }

    # Helper method to execute a query and return the results
    [System.Data.DataTable] ExecuteQuery([string]$query) {
        $dataTable = New-Object System.Data.DataTable
        try {
            $command = New-Object System.Data.SqlClient.SqlCommand($query, $this.ConnectionContext)
            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
            $adapter.Fill($dataTable) | Out-Null
        }
        catch {
            Write-Warning "Error executing query: $query"
            Write-Warning $_.Exception.Message
        }
        return $dataTable
    }

    # Helper method to execute a stored procedure and return the results
    [System.Data.DataTable] ExecuteStoredProcedure([string]$procedureName, [hashtable]$parameters) {
        $dataTable = New-Object System.Data.DataTable
        try {
            $command = New-Object System.Data.SqlClient.SqlCommand($procedureName, $this.ConnectionContext)
            $command.CommandType = [System.Data.CommandType]::StoredProcedure

            foreach ($param in $parameters.GetEnumerator()) {
                $null = $command.Parameters.AddWithValue("@$($param.Key)", $param.Value)
            }

            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
            $adapter.Fill($dataTable) | Out-Null
        }
        catch {
            Write-Warning "Error executing stored procedure: $procedureName"
            Write-Warning $_.Exception.Message
        }
        return $dataTable
    }
}

# Replacement for Microsoft.SqlServer.Replication.ReplicationServer
class DbaReplServer : DbaReplObject {
    [bool]$IsDistributor
    [bool]$IsPublisher
    [string]$DistributionServer
    [string]$DistributionDatabase
    [bool]$DistributorInstalled
    [bool]$DistributorAvailable
    [bool]$HasRemotePublisher
    [System.Collections.ArrayList]$DistributionDatabases = @()

    DbaReplServer() : base() {
        # Default constructor
    }

    DbaReplServer([System.Data.SqlClient.SqlConnection]$ConnectionContext) : base($ConnectionContext) {
        $this.LoadProperties()
    }

    # Load properties from the server using T-SQL instead of RMO
    [bool] LoadProperties() {
        try {
            # Get distributor information using sp_get_distributor
            $query = "EXEC sp_get_distributor"
            $result = $this.ExecuteQuery($query)

            if ($result.Rows.Count -gt 0) {
                $this.IsDistributor = $result.Rows[0]["is_distributor"] -eq $true
                $this.DistributorInstalled = $result.Rows[0]["is_distributor"] -eq $true
                $this.DistributorAvailable = $result.Rows[0]["is_distributor"] -eq $true
                $this.DistributionServer = $result.Rows[0]["distributor"]
                $this.DistributionDatabase = $result.Rows[0]["distribution_db"]
                $this.HasRemotePublisher = $result.Rows[0]["publisher_type"] -eq 1
            }

            # Check if server is a publisher
            $query = "SELECT is_published FROM sys.databases WHERE is_published = 1 OR is_merge_published = 1"
            $result = $this.ExecuteQuery($query)
            $this.IsPublisher = $result.Rows.Count -gt 0

            # Get distribution databases
            if ($this.IsDistributor) {
                $query = "EXEC sp_helpdistributiondb"
                $result = $this.ExecuteQuery($query)
                foreach ($row in $result.Rows) {
                    $distDb = New-Object DbaReplDistributionDatabase
                    $distDb.Name = $row["name"]
                    $distDb.MinDistRetention = $row["min_distretention"]
                    $distDb.MaxDistRetention = $row["max_distretention"]
                    $distDb.HistoryRetention = $row["history_retention"]
                    $distDb.Status = $row["status"]
                    $this.DistributionDatabases.Add($distDb)
                }
            }

            return $true
        }
        catch {
            Write-Warning "Error loading replication server properties"
            Write-Warning $_.Exception.Message
            return $false
        }
    }
}

# Replacement for Microsoft.SqlServer.Replication.DistributionDatabase
class DbaReplDistributionDatabase {
    [string]$Name
    [int]$MinDistRetention
    [int]$MaxDistRetention
    [int]$HistoryRetention
    [int]$Status
}

# Replacement for Microsoft.SqlServer.Replication.ReplicationDatabase
class DbaReplDatabase : DbaReplObject {
    [string]$Name
    [System.Collections.ArrayList]$TransPublications = @()
    [System.Collections.ArrayList]$MergePublications = @()

    DbaReplDatabase() : base() {
        # Default constructor
    }

    DbaReplDatabase([System.Data.SqlClient.SqlConnection]$ConnectionContext, [string]$DatabaseName) : base($ConnectionContext) {
        $this.Name = $DatabaseName
        $this.LoadProperties()
    }

    [bool] LoadProperties() {
        try {
            # Check if database is published
            $query = "SELECT is_published, is_merge_published FROM sys.databases WHERE name = '$($this.Name)'"
            $result = $this.ExecuteQuery($query)

            if ($result.Rows.Count -gt 0) {
                $isPublished = $result.Rows[0]["is_published"] -eq $true
                $isMergePublished = $result.Rows[0]["is_merge_published"] -eq $true

                # Get transactional publications
                if ($isPublished) {
                    $query = "EXEC sp_helppublication @publisher_db = '$($this.Name)'"
                    $result = $this.ExecuteQuery($query)

                    foreach ($row in $result.Rows) {
                        $pub = New-Object DbaReplPublication
                        $pub.ConnectionContext = $this.ConnectionContext
                        $pub.DatabaseName = $this.Name
                        $pub.Name = $row["name"]
                        $pub.Type = "Transactional"
                        $this.TransPublications.Add($pub)
                    }
                }

                # Get merge publications
                if ($isMergePublished) {
                    $query = "EXEC sp_helpmergepublication @publisher_db = '$($this.Name)'"
                    $result = $this.ExecuteQuery($query)

                    foreach ($row in $result.Rows) {
                        $pub = New-Object DbaReplPublication
                        $pub.ConnectionContext = $this.ConnectionContext
                        $pub.DatabaseName = $this.Name
                        $pub.Name = $row["name"]
                        $pub.Type = "Merge"
                        $this.MergePublications.Add($pub)
                    }
                }
            }

            return $true
        }
        catch {
            Write-Warning "Error loading replication database properties for $($this.Name)"
            Write-Warning $_.Exception.Message
            return $false
        }
    }
}

# Replacement for Microsoft.SqlServer.Replication.Publication
class DbaReplPublication : DbaReplObject {
    [string]$Name
    [string]$DatabaseName
    [string]$Type  # Transactional, Merge, or Snapshot
    [System.Collections.ArrayList]$Articles = @()
    [System.Collections.ArrayList]$Subscriptions = @()

    DbaReplPublication() : base() {
        # Default constructor
    }

    [bool] LoadProperties() {
        try {
            # Load articles
            $query = if ($this.Type -eq "Merge") {
                "EXEC sp_helpmergearticle @publication = '$($this.Name)', @publisher_db = '$($this.DatabaseName)'"
            } else {
                "EXEC sp_helparticle @publication = '$($this.Name)', @publisher_db = '$($this.DatabaseName)'"
            }

            $result = $this.ExecuteQuery($query)

            foreach ($row in $result.Rows) {
                $article = New-Object DbaReplArticle
                $article.ConnectionContext = $this.ConnectionContext
                $article.PublicationName = $this.Name
                $article.DatabaseName = $this.DatabaseName
                $article.Name = $row["article"]
                $article.SourceObjectName = $row["source_object"]
                $article.SourceObjectOwner = $row["source_owner"]
                $article.Type = $this.Type
                $this.Articles.Add($article)
            }

            # Load subscriptions
            $query = if ($this.Type -eq "Merge") {
                "EXEC sp_helpmergepullsubscription @publication = '$($this.Name)', @publisher_db = '$($this.DatabaseName)'"
            } else {
                "EXEC sp_helpsubscription @publication = '$($this.Name)', @publisher_db = '$($this.DatabaseName)'"
            }

            $result = $this.ExecuteQuery($query)

            foreach ($row in $result.Rows) {
                $subscription = New-Object DbaReplSubscription
                $subscription.ConnectionContext = $this.ConnectionContext
                $subscription.PublicationName = $this.Name
                $subscription.DatabaseName = $this.DatabaseName
                $subscription.SubscriberName = $row["subscriber_name"]
                $subscription.SubscriptionDBName = $row["subscriber_db"]
                $subscription.Type = $this.Type
                $this.Subscriptions.Add($subscription)
            }

            return $true
        }
        catch {
            Write-Warning "Error loading publication properties for $($this.Name)"
            Write-Warning $_.Exception.Message
            return $false
        }
    }
}

# Replacement for Microsoft.SqlServer.Replication.Article
class DbaReplArticle : DbaReplObject {
    [string]$Name
    [string]$PublicationName
    [string]$DatabaseName
    [string]$SourceObjectName
    [string]$SourceObjectOwner
    [string]$Type  # Transactional, Merge, or Snapshot
}

# Replacement for Microsoft.SqlServer.Replication.Subscription
class DbaReplSubscription : DbaReplObject {
    [string]$PublicationName
    [string]$DatabaseName
    [string]$SubscriberName
    [string]$SubscriptionDBName
    [string]$Type  # Transactional, Merge, or Snapshot
}