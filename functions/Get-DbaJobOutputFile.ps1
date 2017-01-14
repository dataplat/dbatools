Function Get-DbaJobOutputFile
{
<#
.Synopsis
   Returns the Output File for each step of one or many agent job with the Job Names provided dynamically if 
   required for one or more SQL Instances
.DESCRIPTION
   This function returns for one or more SQL Instances the output file value for each step of one or many agent job with the Job Names 
   provided dynamically if required

.PARAMETER SqlServer 
    The SQL Server that you're connecting to. Or an array of SQL Servers

.PARAMETER SQLCredential
    Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER JobName
    The Agent Job Name to provide Output File Path for. Also available dynamically. If ommitted all Agent Jobs will be used

.PARAMETER OpenFile
    Uses Invoke-Item to open the file if it is available

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME -JobName 'The Agent Job' 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance  

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME 

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance   

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME -JobName 'The Agent Job' -OpenFile 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance and open the files if they are available

.EXAMPLE
   $Servers = 'SERVER','SERVER\INSTANCE1'
   Get-DbaJobOutputFile -SqlServer $Servers -JobName 'The Agent Job' -OpenFile 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVER instance and the SERVER\INSTANCE1 and open the files if they are available

.NOTES
   AUTHOR - Rob Sewell https://sqldbawithabeard.com
   DATE - 30/10/2016
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param
(# The Server/instance 
        [Parameter(Mandatory=$true,HelpMessage='The SQL Server Instance', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [object]$SqlServer,
        [Parameter(Mandatory=$false,HelpMessage='SQL Credential', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=1)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory=$false,HelpMessage='Want to open the file')] 
        [switch]$OpenFile)
    DynamicParam { if ($SqlServer) { return (Get-ParamSqlJobs -SqlServer $SqlServer -SqlCredential $SourceSqlCredential) } }

	BEGIN 
    {
		$jobname = $psboundparameters.Jobs
        # Create Table Object
         $table = New-Object system.Data.DataTable $TableName 
         # Create Columns
         $col0 = New-Object system.Data.DataColumn Server,([string])
         $col1 = New-Object system.Data.DataColumn Instance,([string])
         $col2 = New-Object system.Data.DataColumn Job,([string])
         $col3 = New-Object system.Data.DataColumn JobStep,([string])
         $col4 = New-Object system.Data.DataColumn FileName,([string])

         #Add the Columns to the table
         $table.columns.add($col0)
         $table.columns.add($col1)
         $table.columns.add($col2)
         $table.columns.add($col3)
         $table.columns.add($col4)
        function Add-Row 
        {
        # Create a new Row
            $row = $table.NewRow() 
            # Add values to new row
            $row.Server = $Server.ComputerNamePhysicalNetBIOS
            $row.Instance = $Server.Instancename
            $row.Job = $Job.Name
            $row.JobStep = $step.Name
            $row.FileName = $FileName
          
            #Add new row to table
            $table.Rows.Add($row)
        }
         
    }
    PROCESS
    {
        foreach ($instance in $sqlserver)
        {
            $Server = Connect-SqlServer -SqlServer $instance  -SqlCredential $SqlCredential
            $jobs = $Server.JobServer.Jobs
            if ($JobName)
            {
                $Job = $server.JobServer.Jobs[$JobName]
                $Servername = $Server.ComputerNamePhysicalNetBIOS
                foreach($Step in $Job.JobSteps)
                {
                $fileName = $Step.OutputFileName
                if($fileName -eq '')
                {
                    Add-Row 
                }
                else
                {         
                    if($FileName.StartsWith('\\') -eq $false)
            {
                $fileName = '\\' + $Servername + '\' + $Filename.Replace(':','$')
                Add-Row 
            }
            else
            {
              Add-Row 
            }
            if($OpenFile)
            {
                if(Test-Path $fileName)
                {
                    If ($Pscmdlet.ShouldProcess("$FileName", "Opening File $FileName"))
				    {
                        Invoke-Item $fileName
                    }
                }
                else
                {
                    Write-Output 'No File to open'
                }
            }
        }
            }
            }
            else
            {
                foreach($Job in $Jobs)
                {
            $Servername = $Server.ComputerNamePhysicalNetBIOS
            foreach($Step in $Job.JobSteps)
            {
                $fileName = $Step.OutputFileName
                if($fileName -eq '')
                {
                    Add-Row 
                }
                else
                {        
                    if($FileName.StartsWith('\\') -eq $false)
                    {
                $fileName = '\\' + $Servername + '\' + $Filename.Replace(':','$')
                Add-Row 
            }
                    else
                    {
                Add-Row 
            }
                    if($OpenFile)
                    {
                if(Test-Path $fileName)
                {
                    If ($Pscmdlet.ShouldProcess("$FileName", "Opening File $FileName"))
				    {
                        Invoke-Item $fileName
                    }
                }
                else
                {
                    Write-Output 'No File to open'
                }
            }
                }
            }
        }
            }             
            $server.ConnectionContext.Disconnect()
        }
    }
    END
    {
        $table  
    }
}

