function Test-DbaJobOwner {
    <#
        .SYNOPSIS
            Checks SQL Agent Job owners against a login to validate which jobs do not match that owner.

        .DESCRIPTION
            This function checks all SQL Agent Jobs on an instance against a SQL login to validate if that login owns those SQL Agent Jobs or not.

            By default, the function checks against 'sa' for ownership, but the user can pass a specific login if they use something else.

            Only SQL Agent Jobs that do not match this ownership will be displayed.

            Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account

        .PARAMETER SqlInstance
            Specifies the SQL Server instance(s) to scan.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Job
            Specifies the job(s) to process. Options for this list are auto-populated from the server. If unspecified, all jobs will be processed.

        .PARAMETER ExcludeJob
            Specifies the job(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER Login
            Specifies the login that you wish check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed. This must be a valid security principal which exists on the target server.

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Agent, Job, Owner
            Author: Michael Fal (@Mike_Fal), http://mikefal.net

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaJobOwner

        .EXAMPLE
            Test-DbaJobOwner -SqlInstance localhost

            Returns all SQL Agent Jobs where the owner does not match 'sa'.

        .EXAMPLE
            Test-DbaJobOwner -SqlInstance localhost -ExcludeJob 'syspolicy_purge_history'

            Returns SQL Agent Jobs except for the syspolicy_purge_history job

        .EXAMPLE
            Test-DbaJobOwner -SqlInstance localhost -Login DOMAIN\account

            Returns all SQL Agent Jobs where the owner does not match DOMAIN\account. Note
            that Login must be a valid security principal that exists on the target server.
    #>
    [CmdletBinding()]
    [OutputType('System.Object[]')]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Jobs")]
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [Alias("TargetLogin")]
        [string]$Login,
        [switch]$Detailed,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        #connect to the instance and set return array empty
        $return = @()
    }
    process {
        foreach ($servername in $SqlInstance) {
            #connect to the instance
            Write-Message -Level Verbose -Message "Connecting to $servername."
            $server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

            #Validate login
            if ($Login -and ($server.Logins.Name) -notcontains $Login) {
                if ($SqlInstance.count -eq 1) {
                    Stop-Function -Message "Invalid login: $Login."
                    return
                }
                else {
                    Write-Message -Level Warning -Message "$Login is not a valid login on $servername. Moving on."
                    continue
                }
            }
            if ($Login -and $server.Logins[$Login].LoginType -eq 'WindowsGroup') {
                Stop-Function -Message "$Login is a Windows Group and can not be a job owner."
                return
            }

            #Sets the Default Login to sa if the Login Paramater is not set.
            if(!($PSBoundParameters.ContainsKey('Login'))){
                $Login = "sa"
            }
            #sql2000 id property is empty -force target login to 'sa' login
            if ($Login -and ( ($server.VersionMajor -lt 9) -and ([string]::IsNullOrEmpty($Login)) )) {
                $Login = "sa"
            }
            # dynamic sa name for orgs who have changed their sa name
            if ($Login -eq "sa") {
                $Login = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Get database list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to check."
            if ($Job) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            }
            elseif ($ExcludeJob) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $ExcludeJob -notcontains $_.Name }
            }
            else {
                $jobCollection = $server.JobServer.Jobs
            }

            #for each database, create custom object for return set.
            foreach ($j in $jobCollection) {
                Write-Message -Level Verbose -Message "Checking $j"
                $row = [ordered]@{
                    Server       = $server.Name
                    Job          = $j.Name
                    CurrentOwner = $j.OwnerLoginName
                    TargetOwner  = $Login
                    OwnerMatch   = ($j.OwnerLoginName -eq $Login)

                }
                #add each custom object to the return array
                $return += New-Object PSObject -Property $row
            }
            if($Job){
                $results = $return
            }
            else{
                $results = $return | Where-Object {$_.OwnerMatch -eq $False}
            }
        }
    }
    end {
        #return results
            Select-DefaultView -InputObject $results -Property Server,Job,CurrentOwner,TargetOwner,OwnerMatch
    }

}