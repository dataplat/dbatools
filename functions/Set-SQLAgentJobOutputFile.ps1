
Function Set-SQLAgentJobOutPutFile
{
<#
.Synopsis
   Sets the OutPut File for a step of an agent job with the Job Names and steps provided dynamically 
.DESCRIPTION
   Sets the OutPut File for a step of an agent job with the Job Names and steps provided dynamically if required

.PARAMETER SqlServer
    The SQL Server that you're connecting to.

.PARAMETER SQLCredential
    Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER JobName
    The Agent Job Name to provide Output File Path for. Also available dynamically

.PARAMETER JobStep
    The Agent Job Step to provide Output File Path for. Also available dynamically

.PARAMETER OutputFile
    The Full Path to the New Output file
.EXAMPLE
   Set-SQLAgentJobOutPutFile -sqlserver SERVERNAME -JobName 'The Agent Job' -OutPutFile E:\Logs\AgentJobStepOutput.txt

   Sets the Job step for The Agent job on SERVERNAME to E:\Logs\AgentJobStepOutput.txt
.NOTES
   AUTHOR - Rob Sewell https://sqldbawithabeard.com
   DATE - 30/10/2016
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param
(
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
        [Parameter(Mandatory=$true,HelpMessage='The Full Output File Path', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=2)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile,
        [Parameter(Mandatory=$false,HelpMessage='The Job Step name', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [object]$JobStep)

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

    begin 
    {
            # Bind the parameter to a friendly variable
            $JobName = $PsBoundParameters[$ParameterName]
            $Server = Connect-DbaSqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
    }
    process
    {
        $Job = $server.JobServer.Jobs[$JobName]

        If(!$Jobstep)
        {
            if( ($Job.JobSteps).Count -gt 1)
            {
                Write-output "Which Job Step do you wish to add output file to?"
                $JobStep = $Job.JobSteps| Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
            }
            else
            {
                $Jobstep = $Job.JobSteps
            }
        }
#
        Write-Output "Adding $OutputFile to $($JobStep.Name)"
        Write-Output "Current Output File = $(($Jobstep).OutputFileName)"
        try
        {
           If ($Pscmdlet.ShouldProcess($($JobStep.Name), "Changing Output File from $(($Jobstep).OutputFileName) to $OutputFile"))
				{
                    $Jobstep.OutputFileName = $OutputFile
                    $Jobstep.Alter()
                    Write-Output "Successfully added Output file - You can check with Get-SQLAgentJobOutputFile -sqlserver $sqlserver -JobName '$JobName'"
                }
        }
        catch
        {
           Write-Warning "Failed to add $OutputFile to $(($JobStep).Name) for $JobName - Run `$error[0] | fl -force to find out why!"
        }
    }
    end
    {
          $server.ConnectionContext.Disconnect()
    }
}
