Function Get-SQLAgentJobOutPutFile
{
<#
.Synopsis
   Returns the OutPut File for each step of an agent job with the Job Names provided dynamically if 
   required
.DESCRIPTION
   This function returns the output file value for each step in an agent job with the Job Names 
   provided dynamically if required

.PARAMETER SqlServer
    The SQL Server that you're connecting to.

.PARAMETER SQLCredential
    Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER JobName
    The Agent Job Name to provide Output File Path for. Also available dynamically

.PARAMETER OpenFile
    Uses Invoke-Item to open the file if it is available

.EXAMPLE
   Get-SQLAgentJobOutPutFile -instance SERVERNAME -JobName 'The Agent Job' 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance    

.EXAMPLE
   Get-SQLAgentJobOutPutFile -instance SERVERNAME -JobName 'The Agent Job' -OpenFile 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance and open the files if they are available

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
        [string]$sqlserver,
        [Parameter(Mandatory=$false,HelpMessage='SQL Credential', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=1)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory=$false,HelpMessage='Want to open the file')] 
        [switch]$OpenFile)
    DynamicParam {
            # Set the dynamic parameters' name
            $ParameterName = 'JobName'
            
            # Create the dictionary 
            $RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

            # Create the collection of attributes
            $AttributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]
            
            # Create and set the parameters' attributes
            $ParameterAttribute = New-Object -TypeName System.Management.Automation.ParameterAttribute
            $ParameterAttribute.Mandatory = $true
            $ParameterAttribute.Position = 1

            # Add the attributes to the attributes collection
            $AttributeCollection.Add($ParameterAttribute)

            # Generate and set the ValidateSet 
            $Server = Connect-DbaSqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
            $arrSet = ($server.JobServer.Jobs).Name
            $ValidateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($arrSet)

            # Add the ValidateSet to the attributes collection
            $AttributeCollection.Add($ValidateSetAttribute)

            # Create and return the dynamic parameter
            $RuntimeParameter = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameter -ArgumentList ($ParameterName, [string], $AttributeCollection)
            $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
            return $RuntimeParameterDictionary
    }

    begin {
        # Bind the parameter to a friendly variable
        $JobName = $PsBoundParameters[$ParameterName]
    }
    process
    {
    $Job = $server.JobServer.Jobs[$JobName]

        $Servername = $Server.ComputerNamePhysicalNetBIOS

    foreach($Step in $Job.JobSteps)
    {
        $fileName = $Step.OutputFileName

        if($fileName -eq '')
        {
            Write-Output "$($step.Name) has no output file"
        }
        else
        {
            
            if($FileName.StartsWith('\\') -eq $false)
            {
                $fileName = '\\' + $Servername + '\' + $Filename.Replace(':','$')
                Write-Output "$($step.Name) - $fileName"
            }
            else
            {
                Write-Output "$($step.Name) - $fileName "
            }

            if($OpenFile)
            {
                if(Test-Path $fileName)
                {
                    Invoke-Item $fileName
                }
                else
                {
                    Write-Output 'No File to open'
                }
            }
        }
    }
}
end
{
    $server.ConnectionContext.Disconnect()
}
}

