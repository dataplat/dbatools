function Invoke-Parallel {
    <#
    .SYNOPSIS
        Function to control parallel processing using runspaces

    .DESCRIPTION
        Function to control parallel processing using runspaces

            Note that each runspace will not have access to variables and commands loaded in your session or in other runspaces by default.
            This behaviour can be changed with parameters.

    .PARAMETER ScriptFile
        File to run against all input objects.  Must include parameter to take in the input object, or use $args.  Optionally, include parameter to take in parameter.  Example: C:\script.ps1

    .PARAMETER ScriptBlock
        Scriptblock to run against all computers.

        You may use $Using:<Variable> language in PowerShell 3 and later.

            The parameter block is added for you, allowing behaviour similar to foreach-object:
                Refer to the input object as $_.
                Refer to the parameter parameter as $parameter

    .PARAMETER InputObject
        Run script against these specified objects.

    .PARAMETER Parameter
        This object is passed to every script block.  You can use it to pass information to the script block; for example, the path to a logging folder

            Reference this object as $parameter if using the scriptblock parameterset.

    .PARAMETER ImportVariables
        If specified, get user session variables and add them to the initial session state

    .PARAMETER ImportModules
        If specified, get loaded modules and pssnapins, add them to the initial session state

    .PARAMETER Throttle
        Maximum number of threads to run at a single time.

    .PARAMETER SleepTimer
        Milliseconds to sleep after checking for completed runspaces and in a few other spots.  I would not recommend dropping below 200 or increasing above 500

    .PARAMETER RunspaceTimeout
        Maximum time in seconds a single thread can run.  If execution of your code takes longer than this, it is disposed.  Default: 0 (seconds)

        WARNING:  Using this parameter requires that maxQueue be set to throttle (it will be by default) for accurate timing.  Details here:
        http://gallery.technet.microsoft.com/Run-Parallel-Parallel-377fd430

    .PARAMETER NoCloseOnTimeout
        Do not dispose of timed out tasks or attempt to close the runspace if threads have timed out. This will prevent the script from hanging in certain situations where threads become non-responsive, at the expense of leaking memory within the PowerShell host.

    .PARAMETER MaxQueue
        Maximum number of powershell instances to add to runspace pool.  If this is higher than $throttle, $timeout will be inaccurate

        If this is equal or less than throttle, there will be a performance impact

        The default value is $throttle times 3, if $runspaceTimeout is not specified
        The default value is $throttle, if $runspaceTimeout is specified

    .PARAMETER LogFile
        Path to a file where we can log results, including run time for each thread, whether it completes, completes with errors, or times out.

    .PARAMETER AppendLog
        Append to existing log

    .PARAMETER Quiet
        Disable progress bar

    .EXAMPLE
        Each example uses Test-ForPacs.ps1 which includes the following code:
            param($computer)

            if(test-connection $computer -count 1 -quiet -BufferSize 16){
                $object = [pscustomobject] @{
                    Computer=$computer;
                    Available=1;
                    Kodak=$(
                        if((test-path "\\$computer\c$\users\public\desktop\Kodak Direct View Pacs.url") -or (test-path "\\$computer\c$\documents and settings\all users\desktop\Kodak Direct View Pacs.url") ){"1"}else{"0"}
                    )
                }
            }
            else{
                $object = [pscustomobject] @{
                    Computer=$computer;
                    Available=0;
                    Kodak="NA"
                }
            }

            $object

    .EXAMPLE
        Invoke-Parallel -scriptfile C:\public\Test-ForPacs.ps1 -inputobject $(get-content C:\pcs.txt) -runspaceTimeout 10 -throttle 10

            Pulls list of PCs from C:\pcs.txt,
            Runs Test-ForPacs against each
            If any query takes longer than 10 seconds, it is disposed
            Only run 10 threads at a time

    .EXAMPLE
        Invoke-Parallel -scriptfile C:\public\Test-ForPacs.ps1 -inputobject c-is-ts-91, c-is-ts-95

            Runs against c-is-ts-91, c-is-ts-95 (-computername)
            Runs Test-ForPacs against each

    .EXAMPLE
        $stuff = [pscustomobject] @{
            ContentFile = "windows\system32\drivers\etc\hosts"
            Logfile = "C:\temp\log.txt"
        }

        $computers | Invoke-Parallel -parameter $stuff {
            $contentFile = join-path "\\$_\c$" $parameter.contentfile
            Get-Content $contentFile |
                set-content $parameter.logfile
        }

        This example uses the parameter argument.  This parameter is a single object.  To pass multiple items into the script block, we create a custom object (using a PowerShell v3 language) with properties we want to pass in.

        Inside the script block, $parameter is used to reference this parameter object.  This example sets a content file, gets content from that file, and sets it to a predefined log file.

    .EXAMPLE
        $test = 5
        1..2 | Invoke-Parallel -ImportVariables {$_ * $test}

        Add variables from the current session to the session state.  Without -ImportVariables $Test would not be accessible

    .EXAMPLE
        $test = 5
        1..2 | Invoke-Parallel {$_ * $Using:test}

        Reference a variable from the current session with the $Using:<Variable> syntax.  Requires PowerShell 3 or later. Note that -ImportVariables parameter is no longer necessary.

    .FUNCTIONALITY
        PowerShell Language

    .NOTES
        Credit to Boe Prox for the base runspace code and $Using implementation
            http://learn-powershell.net/2012/05/10/speedy-network-information-query-using-powershell/
            http://gallery.technet.microsoft.com/scriptcenter/Speedy-Network-Information-5b1406fb#content
            https://github.com/proxb/PoshRSJob/

        Credit to T Bryce Yehl for the Quiet and NoCloseOnTimeout implementations

        Credit to Sergei Vorobev for the many ideas and contributions that have improved functionality, reliability, and ease of use

    .LINK
        https://github.com/RamblingCookieMonster/Invoke-Parallel
    #>
    [cmdletbinding(DefaultParameterSetName = 'ScriptBlock')]
    param (
        [Parameter(ParameterSetName = 'ScriptBlock')]
        [System.Management.Automation.ScriptBlock]$ScriptBlock,

        [Parameter(ParameterSetName = 'ScriptFile')]
        [ValidateScript( {Test-Path $_ -pathtype leaf})]
        $ScriptFile,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('CN', '__Server', 'IPAddress', 'Server', 'ComputerName')]
        [PSObject]$InputObject,
        [string]$ObjectName = "input objects",
        [string]$Activity = "Running Query",
        [string]$Status = "Starting threads",

        [PSObject]$Parameter,

        [switch]$ImportVariables,
        [switch]$ImportModules,
        [switch]$ImportFunctions,

        [int]$Throttle = 20,
        [int]$SleepTimer = 200,
        [int]$RunspaceTimeout = 0,
        [switch]$NoCloseOnTimeout = $false,
        [int]$MaxQueue,

        [validatescript( {Test-Path (Split-Path $_ -parent)})]
        [switch] $AppendLog = $false,
        [string]$LogFile,

        [switch] $Quiet = $false
    )
    begin {
        # save default runspace
        $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        #No max queue specified?  Estimate one.
        #We use the script scope to resolve an odd PowerShell 2 issue where MaxQueue isn't seen later in the function
        if ( -not $PSBoundParameters.ContainsKey('MaxQueue') ) {
            if ($RunspaceTimeout -ne 0) { $script:MaxQueue = $Throttle }
            else { $script:MaxQueue = $Throttle * 3 }
        } else {
            $script:MaxQueue = $MaxQueue
        }
        $ProgressId = Get-Random
        Write-Verbose "Throttle: '$throttle' SleepTimer '$sleepTimer' runSpaceTimeout '$runspaceTimeout' maxQueue '$maxQueue' logFile '$logFile'"

        #If they want to import variables or modules, create a clean runspace, get loaded items, use those to exclude items
        if ($ImportVariables -or $ImportModules -or $ImportFunctions) {
            $StandardUserEnv = [powershell]::Create().addscript( {

                    #Get modules, snapins, functions in this clean runspace
                    $Modules = Get-Module | Select-Object -ExpandProperty Name
                    $Snapins = Get-PSSnapin | Select-Object -ExpandProperty Name
                    $Functions = Get-ChildItem function:\ | Select-Object -ExpandProperty Name

                    #Get variables in this clean runspace
                    #Called last to get vars like $? into session
                    $Variables = Get-Variable | Select-Object -ExpandProperty Name

                    #Return a hashtable where we can access each.
                    @{
                        Variables = $Variables
                        Modules   = $Modules
                        Snapins   = $Snapins
                        Functions = $Functions
                    }
                }).invoke()[0]

            if ($ImportVariables) {
                #Exclude common parameters, bound parameters, and automatic variables
                Function _temp {[cmdletbinding(SupportsShouldProcess)] param() }
                $VariablesToExclude = @( (Get-Command _temp | Select-Object -ExpandProperty parameters).Keys + $PSBoundParameters.Keys + $StandardUserEnv.Variables )
                Write-Verbose "Excluding variables $( ($VariablesToExclude | Sort-Object ) -join ", ")"

                # we don't use 'Get-Variable -Exclude', because it uses regexps.
                # One of the veriables that we pass is '$?'.
                # There could be other variables with such problems.
                # Scope 2 required if we move to a real module
                $UserVariables = @( Get-Variable | Where-Object { -not ($VariablesToExclude -contains $_.Name) } )
                Write-Verbose "Found variables to import: $( ($UserVariables | Select-Object -expandproperty Name | Sort-Object ) -join ", " | Out-String).`n"
            }
            if ($ImportModules) {
                $UserModules = @( Get-Module | Where-Object {$StandardUserEnv.Modules -notcontains $_.Name -and (Test-Path $_.Path -ErrorAction SilentlyContinue)} | Select-Object -ExpandProperty Path )
                $UserSnapins = @( Get-PSSnapin | Select-Object -ExpandProperty Name | Where-Object {$StandardUserEnv.Snapins -notcontains $_ } )
            }
            if ($ImportFunctions) {
                $UserFunctions = @( Get-ChildItem function:\ | Where-Object { $StandardUserEnv.Functions -notcontains $_.Name } )
            }
        }

        #region functions
        Function Get-RunspaceData {
            [cmdletbinding()]
            param( [switch]$Wait )
            #loop through runspaces
            #if $wait is specified, keep looping until all complete
            Do {
                #set more to false for tracking completion
                $more = $false

                #Progress bar if we have inputobject count (bound parameter)
                if (-not $Quiet) {
                    $writeProgressSplat = @{
                        Id               = $ProgressId
                        Activity         = $Activity
                        Status           = $Status
                        CurrentOperation = "$startedCount threads defined - $totalCount $ObjectName - $script:completedCount $ObjectName processed"
                        PercentComplete  = try { $script:completedCount / $totalCount * 100 } catch { 0 }
                    }
                    Write-Progress @writeProgressSplat
                }

                #run through each runspace.
                Foreach ($runspace in $runspaces) {

                    #get the duration - inaccurate
                    $currentdate = Get-Date
                    $runtime = $currentdate - $runspace.startTime
                    $runMin = [math]::Round( $runtime.totalminutes , 2 )

                    #set up log object
                    $log = "" | Select-Object Date, Action, Runtime, Status, Details
                    $log.Action = "Removing:'$($runspace.object)'"
                    $log.Date = $currentdate
                    $log.Runtime = "$runMin minutes"

                    #If runspace completed, end invoke, dispose, recycle, counter++
                    If ($runspace.Runspace.isCompleted) {

                        $script:completedCount++

                        #check if there were errors
                        if ($runspace.powershell.Streams.Error.Count -gt 0) {
                            #set the logging info and move the file to completed
                            $log.status = "CompletedWithErrors"
                            Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                            foreach ($ErrorRecord in $runspace.powershell.Streams.Error) {
                                Write-Error -ErrorRecord $ErrorRecord
                            }
                        } else {
                            #add logging details and cleanup
                            $log.status = "Completed"
                            Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                        }

                        #everything is logged, clean up the runspace
                        $runspace.powershell.EndInvoke($runspace.Runspace)
                        $runspace.powershell.dispose()
                        $runspace.Runspace = $null
                        $runspace.powershell = $null
                    }
                    #If runtime exceeds max, dispose the runspace
                    ElseIf ( $runspaceTimeout -ne 0 -and $runtime.totalseconds -gt $runspaceTimeout) {
                        $script:completedCount++
                        $timedOutTasks = $true

                        #add logging details and cleanup
                        $log.status = "TimedOut"
                        Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                        Write-Error "Runspace timed out at $($runtime.totalseconds) seconds for the object:`n$($runspace.object | out-string)"

                        #Depending on how it hangs, we could still get stuck here as dispose calls a synchronous method on the powershell instance
                        if (!$noCloseOnTimeout) { $runspace.powershell.dispose() }
                        $runspace.Runspace = $null
                        $runspace.powershell = $null
                        $completedCount++
                    }

                    #If runspace isn't null set more to true
                    ElseIf ($runspace.Runspace -ne $null ) {
                        $log = $null
                        $more = $true
                    }

                    #log the results if a log file was indicated
                    if ($logFile -and $log) {
                        ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1] | out-file $LogFile -append
                    }
                }

                #Clean out unused runspace jobs
                $temphash = $runspaces.clone()
                $temphash | Where-Object { $_.runspace -eq $Null } | ForEach-Object {
                    $Runspaces.remove($_)
                }

                #sleep for a bit if we will loop again
                if ($PSBoundParameters['Wait']) { Start-Sleep -milliseconds $SleepTimer }

                #Loop again only if -wait parameter and there are more runspaces to process
            } while ($more -and $PSBoundParameters['Wait'])

            #End of runspace function
        }
        #endregion functions

        #region Init

        if ($PSCmdlet.ParameterSetName -eq 'ScriptFile') {
            $ScriptBlock = [scriptblock]::Create( $(Get-Content $ScriptFile | out-string) )
        } elseif ($PSCmdlet.ParameterSetName -eq 'ScriptBlock') {
            #Start building parameter names for the param block
            [string[]]$ParamsToAdd = '$_'
            if ( $PSBoundParameters.ContainsKey('Parameter') ) {
                $ParamsToAdd += '$Parameter'
            }

            $UsingVariableData = $Null

            # This code enables $Using support through the AST.
            # This is entirely from  Boe Prox, and his https://github.com/proxb/PoshRSJob module; all credit to Boe!

            if ($PSVersionTable.PSVersion.Major -gt 2) {
                #Extract using references
                $UsingVariables = $ScriptBlock.ast.FindAll( {$args[0] -is [System.Management.Automation.Language.UsingExpressionAst]}, $True)

                If ($UsingVariables) {
                    $List = New-Object 'System.Collections.Generic.List`1[System.Management.Automation.Language.VariableExpressionAst]'
                    ForEach ($Ast in $UsingVariables) {
                        [void]$list.Add($Ast.SubExpression)
                    }

                    $UsingVar = $UsingVariables | Group-Object -Property SubExpression | ForEach-Object {$_.Group | Select-Object -First 1}

                    #Extract the name, value, and create replacements for each
                    $UsingVariableData = ForEach ($Var in $UsingVar) {
                        try {
                            $Value = Get-Variable -Name $Var.SubExpression.VariablePath.UserPath -ErrorAction Stop
                            [pscustomobject]@{
                                Name       = $Var.SubExpression.Extent.Text
                                Value      = $Value.Value
                                NewName    = ('$__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
                                NewVarName = ('__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
                            }
                        } catch {
                            Write-Error "$($Var.SubExpression.Extent.Text) is not a valid Using: variable."
                        }
                    }
                    $ParamsToAdd += $UsingVariableData | Select-Object -ExpandProperty NewName -Unique

                    $NewParams = $UsingVariableData.NewName -join ', '
                    $Tuple = [Tuple]::Create($list, $NewParams)
                    $bindingFlags = [Reflection.BindingFlags]"Default,NonPublic,Instance"
                    $GetWithInputHandlingForInvokeCommandImpl = ($ScriptBlock.ast.gettype().GetMethod('GetWithInputHandlingForInvokeCommandImpl', $bindingFlags))

                    $StringScriptBlock = $GetWithInputHandlingForInvokeCommandImpl.Invoke($ScriptBlock.ast, @($Tuple))

                    $ScriptBlock = [scriptblock]::Create($StringScriptBlock)

                    Write-Verbose $StringScriptBlock
                }
            }

            $ScriptBlock = $ExecutionContext.InvokeCommand.NewScriptBlock("param($($ParamsToAdd -Join ", "))`r`n" + $Scriptblock.ToString())
        } else {
            Throw "Must provide ScriptBlock or ScriptFile"; Break
        }

        Write-Debug "`$ScriptBlock: $($ScriptBlock | Out-String)"
        Write-Verbose "Creating runspace pool and session states"

        #If specified, add variables and modules/snapins to session state
        $sessionstate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $sessionstate.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'WarningPreference', 'SilentlyContinue', $null))
        if ($ImportVariables -and $UserVariables.count -gt 0) {
            foreach ($Variable in $UserVariables) {
                $sessionstate.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $Variable.Name, $Variable.Value, $null) )
            }
        }
        if ($ImportModules) {
            if ($UserModules.count -gt 0) {
                foreach ($ModulePath in $UserModules) {
                    $sessionstate.ImportPSModule($ModulePath)
                }
            }
            if ($UserSnapins.count -gt 0) {
                foreach ($PSSnapin in $UserSnapins) {
                    [void]$sessionstate.ImportPSSnapIn($PSSnapin, [ref]$null)
                }
            }
        }
        if ($ImportFunctions -and $UserFunctions.count -gt 0) {
            foreach ($FunctionDef in $UserFunctions) {
                $sessionstate.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $FunctionDef.Name, $FunctionDef.ScriptBlock))
            }
        }

        #Create runspace pool
        $runspacepool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $sessionstate, $Host)
        $runspacepool.Open()

        Write-Verbose "Creating empty collection to hold runspace jobs"
        $Script:runspaces = New-Object System.Collections.ArrayList

        #If inputObject is bound get a total count and set bound to true
        $bound = $PSBoundParameters.keys -contains "InputObject"
        if (-not $bound) {
            [System.Collections.ArrayList]$allObjects = @()
        }

        #Set up log file if specified
        if ( $LogFile -and (-not (Test-Path $LogFile) -or $AppendLog -eq $false)) {
            New-Item -ItemType file -Path $logFile -Force | Out-Null
            ("" | Select-Object -Property Date, Action, Runtime, Status, Details | ConvertTo-Csv -NoTypeInformation -Delimiter ";")[0] | Out-File $LogFile
        }

        #write initial log entry
        $log = "" | Select-Object -Property Date, Action, Runtime, Status, Details
        $log.Date = Get-Date
        $log.Action = "Batch processing started"
        $log.Runtime = $null
        $log.Status = "Started"
        $log.Details = $null
        if ($logFile) {
            ($log | convertto-csv -Delimiter ";" -NoTypeInformation)[1] | Out-File $LogFile -Append
        }
        $timedOutTasks = $false
        #endregion INIT
    }
    process {
        #add piped objects to all objects or set all objects to bound input object parameter
        if ($bound) {
            $allObjects = $InputObject
        } else {
            [void]$allObjects.add( $InputObject )
        }
    }
    end {
        #Use Try/Finally to catch Ctrl+C and clean up.
        try {
            #counts for progress
            $totalCount = $allObjects.count
            $script:completedCount = 0
            $startedCount = 0
            foreach ($object in $allObjects) {
                #region add scripts to runspace pool
                #Create the powershell instance, set verbose if needed, supply the scriptblock and parameters
                $powershell = [powershell]::Create()

                if ($VerbosePreference -eq 'Continue') {
                    [void]$PowerShell.AddScript( {$VerbosePreference = 'Continue'})
                }

                [void]$PowerShell.AddScript($ScriptBlock).AddArgument($object)

                if ($parameter) {
                    [void]$PowerShell.AddArgument($parameter)
                }

                # $Using support from Boe Prox
                if ($UsingVariableData) {
                    Foreach ($UsingVariable in $UsingVariableData) {
                        Write-Verbose "Adding $($UsingVariable.Name) with value: $($UsingVariable.Value)"
                        [void]$PowerShell.AddArgument($UsingVariable.Value)
                    }
                }

                #Add the runspace into the powershell instance
                $powershell.RunspacePool = $runspacepool

                #Create a temporary collection for each runspace
                $temp = "" | Select-Object PowerShell, StartTime, object, Runspace
                $temp.PowerShell = $powershell
                $temp.StartTime = Get-Date
                $temp.object = $object

                #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
                $temp.Runspace = $powershell.BeginInvoke()
                $startedCount++

                #Add the temp tracking info to $runspaces collection
                Write-Verbose ( "Adding {0} to collection at {1}" -f $temp.object, $temp.starttime.tostring() )
                $runspaces.Add($temp) | Out-Null

                #loop through existing runspaces one time
                Get-RunspaceData

                #If we have more running than max queue (used to control timeout accuracy)
                #Script scope resolves odd PowerShell 2 issue
                $firstRun = $true
                while ($runspaces.count -ge $Script:MaxQueue) {
                    #give verbose output
                    if ($firstRun) {
                        Write-Verbose "$($runspaces.count) items running - exceeded $Script:MaxQueue limit."
                    }
                    $firstRun = $false

                    #run get-runspace data and sleep for a short while
                    Get-RunspaceData
                    Start-Sleep -Milliseconds $sleepTimer
                }
                #endregion add scripts to runspace pool
            }
            Write-Verbose ( "Finish processing the remaining runspace jobs: {0}" -f ( @($runspaces | Where-Object {$_.Runspace -ne $Null}).Count) )

            Get-RunspaceData -wait
            if (-not $quiet) {
                Write-Progress -Id $ProgressId -Activity $Activity -Status $Status -Completed
            }
        } finally {
            #Close the runspace pool, unless we specified no close on timeout and something timed out
            if ( ($timedOutTasks -eq $false) -or ( ($timedOutTasks -eq $true) -and ($noCloseOnTimeout -eq $false) ) ) {
                Write-Verbose "Closing the runspace pool"
                $runspacepool.close()
            }
            #collect garbage
            [gc]::Collect()
        }
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
    }
}