function Find-DbaUserObject {
    <#
    .SYNOPSIS
        Searches SQL Server to find user-owned objects (i.e. not dbo or sa) or for any object owned by a specific user specified by the Pattern parameter.

    .DESCRIPTION
        Looks at the below list of objects to see if they are either owned by a user or a specific user (using the parameter -Pattern)
        Database Owner
        Agent Job Owner
        Used in Credential
        USed in Proxy
        SQL Agent Steps using a Proxy
        Endpoints
        Server Roles
        Database Schemas
        Database Roles
        Database Assembles
        Database Synonyms

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Pattern
        The regex pattern that the command will search for

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Object
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaUserObject

    .EXAMPLE
        PS C:\> Find-DbaUserObject -SqlInstance DEV01 -Pattern ad\stephen

        Searches user objects for owner ad\stephen

    .EXAMPLE
        PS C:\> Find-DbaUserObject -SqlInstance DEV01 -Verbose

        Shows all user owned (non-sa, non-dbo) objects and verbose output

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Pattern,
        [switch]$EnableException
    )
    begin {
        if ($Pattern -match '^[\w\d\.-]+\\[\w\d\.-]+$') {
            Write-Message -Level Verbose -Message "Too few slashes, adding extra as required by regex"
            $Pattern = $Pattern.Replace('\', '\\')
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $saname = Get-SaLoginName $server

            ## Credentials
            if (-not $pattern) {
                Write-Message -Level Verbose -Message "Gathering data on instance objects"
                $creds = $server.Credentials
                $proxies = $server.JobServer.ProxyAccounts
                $endPoints = $server.Endpoints | Where-Object { $_.Owner -ne $saname }

                Write-Message -Level Verbose -Message "Gather data on Agent Jobs ownership"
                #Variable marked as unused by PSScriptAnalyzer
                #$jobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $saname }
            } else {
                Write-Message -Level Verbose -Message "Gathering data on instance objects"
                $creds = $server.Credentials | Where-Object { $_.Identity -match $pattern }
                $proxies = $server.JobServer.ProxyAccounts | Where-Object { $_.CredentialIdentity -match $pattern }
                $endPoints = $server.Endpoints | Where-Object { $_.Owner -match $pattern }

                Write-Message -Level Verbose -Message "Gather data on Agent Jobs ownership"
                #Variable marked as unused by PSScriptAnalyzer
                #$jobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -match $pattern }
            }

            ## dbs
            if (-not $pattern) {
                foreach ($db in $server.Databases | Where-Object { $_.Owner -ne $saname }) {
                    Write-Message -Level Verbose -Message "checking if $db is owned "

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database"
                        Owner        = $db.Owner
                        Name         = $db.Name
                        Parent       = $db.Parent.Name
                    }
                }
            } else {
                foreach ($db in $server.Databases | Where-Object { $_.Owner -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database"
                        Owner        = $db.Owner
                        Name         = $db.Name
                        Parent       = $db.Parent.Name
                    }
                }
            }

            ## agent jobs
            if (-not $pattern) {
                foreach ($job in $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $saname }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Agent Job"
                        Owner        = $job.OwnerLoginName
                        Name         = $job.Name
                        Parent       = $job.Parent.Name
                    }
                }
            } else {
                foreach ($job in $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Agent Job"
                        Owner        = $job.OwnerLoginName
                        Name         = $job.Name
                        Parent       = $job.Parent.Name
                    }
                }
            }

            ## credentials
            foreach ($cred in $creds) {
                ## list credentials using the account

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Credential"
                    Owner        = $cred.Identity
                    Name         = $cred.Name
                    Parent       = $cred.Parent.Name
                }
            }

            ## proxies
            foreach ($proxy in $proxies) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Proxy"
                    Owner        = $proxy.CredentialIdentity
                    Name         = $proxy.Name
                    Parent       = $proxy.Parent.Name
                }

                ## list agent jobs steps using proxy
                foreach ($job in $server.JobServer.Jobs) {
                    foreach ($step in $job.JobSteps | Where-Object { $_.ProxyName -eq $proxy.Name }) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Type         = "Agent Step"
                            Owner        = $step.ProxyName
                            Name         = $step.Name
                            Parent       = $step.Parent.Name #$step.Name
                        }
                    }
                }
            }


            ## endpoints
            foreach ($endPoint in $endPoints) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Endpoint"
                    Owner        = $endpoint.Owner
                    Name         = $endPoint.Name
                    Parent       = $endPoint.Parent.Name
                }
            }

            ## Server Roles
            if (-not $pattern) {
                foreach ($role in $server.Roles | Where-Object { $_.Owner -ne $saname }) {
                    Write-Message -Level Verbose -Message "checking if $db is owned "
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Server Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }
            } else {
                foreach ($role in $server.Roles | Where-Object { $_.Owner -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Server Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }
            }

            ## Loop internal database
            foreach ($db in $server.Databases | Where-Object IsAccessible) {
                Write-Message -Level Verbose -Message "Gather user owned object in database: $db"
                ##schemas
                $sysSchemas = "DatabaseMailUserRole", "db_ssisadmin", "db_ssisltduser", "db_ssisoperator", "SQLAgentOperatorRole", "SQLAgentReaderRole", "SQLAgentUserRole", "TargetServersRole", "RSExecRole"

                if (-not $pattern) {
                    $schemas = $db.Schemas | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" -and $sysSchemas -notcontains $_.Owner }
                } else {
                    $schemas = $db.Schemas | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern -and $sysSchemas -notcontains $_.Owner }
                }
                foreach ($schema in $schemas) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Schema"
                        Owner        = $schema.Owner
                        Name         = $schema.Name
                        Parent       = $schema.Parent.Name
                    }
                }

                ## database roles
                if (-not $pattern) {
                    $roles = $db.Roles | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $roles = $db.Roles | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }
                foreach ($role in $roles) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }

                ## assembly
                if (-not $pattern) {
                    $assemblies = $db.Assemblies | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $assemblies = $db.Assemblies | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }

                foreach ($assembly in $assemblies) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Assembly"
                        Owner        = $assembly.Owner
                        Name         = $assembly.Name
                        Parent       = $assembly.Parent.Name
                    }
                }

                ## synonyms
                if (-not $pattern) {
                    $synonyms = $db.Synonyms | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $synonyms = $db.Synonyms | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }

                foreach ($synonym in $synonyms) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Synonyms"
                        Owner        = $synonym.Owner
                        Name         = $synonym.Name
                        Parent       = $synonym.Parent.Name
                    }
                }
            }
        }
    }
}