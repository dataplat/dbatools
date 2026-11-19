#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Rename-DbaDatabase hop script, SECOND half (#region filename onward). See the
/// ProcessScriptHead partial for the split rationale.
/// </summary>
public sealed partial class RenameDbaDatabaseCommand
{
    internal const string ProcessScriptTail = """
            #region filename
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
            }
            if (!$failed -and $FileName) {

                $New_FileNames = @{ }
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $New_FileNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $New_FileNames[$fn] = 1
                }
                # we need to inspect what files are in the same directory
                # to avoid failing the process because the move won't work
                # here we have a dict keyed by instance and then keyed by path
                if ( !$InstanceFiles.ContainsKey($Server_Id) ) {
                    $InstanceFiles[$Server_Id] = @{ }
                }
                foreach ($fn in $New_FileNames.Keys) {
                    $dirname = [IO.Path]::GetDirectoryName($fn)
                    if ( !$InstanceFiles[$Server_Id].ContainsKey($dirname) ) {
                        $InstanceFiles[$Server_Id][$dirname] = @{ }
                        try {
                            $dirfiles = Get-DbaFile -SqlInstance $server -Path $dirname -EnableException
                        } catch {
                            Write-Message -Level Warning -Message "Failed to enumerate existing files at $dirname, move could go wrong" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                        }
                        foreach ($f in $dirfiles) {
                            $InstanceFiles[$Server_Id][$dirname][$f.Filename] = 1
                        }
                    }
                }
                $FNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $FG_Files = @($fg.Files)
                    foreach ($logical in $FG_Files) {
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $FNName = $logical.FileName
                        $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                        $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                        $Orig_Placeholder = $Orig_FNNameLeaf
                        if ($ReplaceBefore) {
                            # at Filename level, we need to worry about database name, filegroup name and logical file name
                            $dbKey = Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name
                            $fgKey = Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name
                            $lgKey = Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name
                            if ($dbKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($dbKey, '')
                            }
                            if ($fgKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($fgKey, '')
                            }
                            if ($lgKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($lgKey, '')
                            }
                        }
                        $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                        $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")

                        while ($logical.FileName -ne $FinalFNName) {
                            if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                $FNCounter += 1
                                $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))"
                                )
                            } else {
                                break
                            }
                        }
                        if ($logical.FileName -eq $FinalFNName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary (on FileGroup $($fg.Name) (on $db))" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.FileName = $FinalFNName
                                    $db.Alter()
                                }
                                $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                $Entities_Before['FNN'][$FNName] = $FinalFNName
                                $Pending_Renames += [PSCustomObject]@{
                                    Source      = $FNName
                                    Destination = $FinalFNName
                                }
                            } catch {
                                Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    if (!$failed) {
                        $FG_Files = @($db.Logfiles)
                        foreach ($logical in $FG_Files) {
                            $FNName = $logical.FileName
                            $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                            $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                            $Orig_Placeholder = $Orig_FNNameLeaf
                            if ($ReplaceBefore) {
                                # at Filename level, we need to worry about database name, filegroup name and logical file name
                                $dbKey = Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name
                                $fgKey = Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name
                                $lgKey = Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name
                                if ($dbKey) {
                                    $Orig_Placeholder = $Orig_Placeholder.Replace($dbKey, '')
                                }
                                if ($fgKey) {
                                    $Orig_Placeholder = $Orig_Placeholder.Replace($fgKey, '')
                                }
                                if ($lgKey) {
                                    $Orig_Placeholder = $Orig_Placeholder.Replace($lgKey, '')
                                }
                            }
                            $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                                '<FT>', 'LOG').Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                            $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")
                            while ($logical.FileName -ne $FinalFNName) {
                                if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                    $FNCounter += 1
                                    $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))")
                                } else {
                                    break
                                }
                            }
                            if ($logical.FileName -eq $FinalFNName) {
                                Write-Message -Level VeryVerbose -Message "No rename necessary for $($logical.FileName) (LOG on (on $db))" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (LOG)")) {
                                try {
                                    if (!$Preview) {
                                        $logical.FileName = $FinalFNName
                                        $db.Alter()
                                    }
                                    $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                    $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                    $Entities_Before['FNN'][$FNName] = $FinalFNName
                                    $Pending_Renames += [PSCustomObject]@{
                                        Source      = $FNName
                                        Destination = $FinalFNName
                                    }
                                } catch {
                                    Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                                    # stop any further renames
                                    $failed = $true
                                    break
                                }
                            }
                        }
                    }

                }
                #endregion filename
                #region move
                $ComputerName = $null
                $Final_Renames = New-Object System.Collections.ArrayList
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use rename-item
                    $ComputerName = $server.ComputerName
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (!($testPS)) {
                        # let's try to resolve it to a more qualified name, without "cutting" knowledge about the domain (only $server.Name possibly holds the complete info)
                        $Resolved = (Resolve-DbaNetworkName -ComputerName $server.Name).FullComputerName
                        if ($SqlCredential) {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -Credential $SqlCredential -ErrorAction Stop
                        } else {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -ErrorAction Stop
                        }
                        if ($testPS) {
                            $ComputerName = $Resolved
                        }
                    } else {
                        $ComputerName = $server.ComputerName
                    }
                }
                foreach ($op in $pending_renames) {
                    if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                        $null = $Final_Renames.Add([PSCustomObject]@{
                                Source       = $op.Source
                                Destination  = $op.Destination
                                ComputerName = $ComputerName
                            })
                    } else {
                        if ($null -eq $ComputerName) {
                            # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                            if (Test-Path (Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source)) {
                                $null = $Final_Renames.Add([PSCustomObject]@{
                                        Source       = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source
                                        Destination  = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Destination
                                        ComputerName = $server.ComputerName
                                    })
                            } else {
                                # flag the impossible rename ($ComputerName is $null)
                                $null = $Final_Renames.Add([PSCustomObject]@{
                                        Source       = $op.Source
                                        Destination  = $op.Destination
                                        ComputerName = $ComputerName
                                    })
                            }
                        } else {
                            # we can do renames in a remote pssession
                            $null = $Final_Renames.Add([PSCustomObject]@{
                                    Source       = $op.Source
                                    Destination  = $op.Destination
                                    ComputerName = $ComputerName
                                })
                        }
                    }
                }
                $Status = 'FULL'
                if (!$failed -and ($SetOffline -or $Move) -and $Final_Renames) {
                    if (!$Move) {
                        Write-Message -Level VeryVerbose -Message "Setting the database offline. You are in charge of moving the files to the new location" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                        # because renames still need to be dealt with
                        $Status = 'PARTIAL'
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "File Rename required, setting db offline")) {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Offline -Force
                            if ($SetState.Status -ne 'OFFLINE') {
                                Write-Message -Level Warning -Message "Setting db offline failed, You are in charge of moving the files to the new location" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                                # because it was impossible to set the database offline
                                $Status = 'PARTIAL'
                            } else {
                                try {
                                    while ($Final_Renames.Count -gt 0) {
                                        $op = $Final_Renames.Item(0)
                                        if ($null -eq $op.ComputerName) {
                                            Stop-Function -Message "No access to physical files for renames" -FunctionName Rename-DbaDatabase
                                        } else {
                                            Write-Message -Level VeryVerbose -Message "Moving file $($op.Source) to $($op.Destination)" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                                            if (!$Preview) {
                                                $scriptBlock = {
                                                    $op = $args[0]
                                                    Rename-Item -Path $op.Source -NewName $op.Destination
                                                }
                                                Invoke-Command2 -ComputerName $op.ComputerName -Credential $sqlCredential -ScriptBlock $scriptBlock -ArgumentList $op
                                            }
                                        }
                                        $null = $Final_Renames.RemoveAt(0)
                                    }
                                } catch {
                                    $failed = $true
                                    # because a rename operation failed
                                    $Status = 'PARTIAL'
                                    Stop-Function -Message "Failed to rename $($op.Source) to $($op.Destination), you are in charge of moving the files to the new location" -ErrorRecord $_ -Target $instance -Exception $_.Exception -Continue -FunctionName Rename-DbaDatabase
                                }
                                if (!$failed) {
                                    if ($PSCmdlet.ShouldProcess($db, "Setting database online")) {
                                        $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Online -Force
                                        if ($SetState.Status -ne 'ONLINE') {
                                            Write-Message -Level Warning -Message "Setting db online failed" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                                            # because renames were done, but the database didn't wake up
                                            $Status = 'PARTIAL'
                                        } else {
                                            $Status = 'FULL'
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    # because of a previous error with renames to do
                    $Status = 'PARTIAL'
                }
            } else {
                if (!$failed) {
                    # because no previous error and not filename
                    $Status = 'FULL'
                } else {
                    # because previous errors and not filename
                    $Status = 'PARTIAL'
                }
            }
            #endregion move
            # remove entities that match for the output
            foreach ($k in $Entities_Before.Keys) {
                $ToRemove = $Entities_Before[$k].GetEnumerator() | Where-Object { $_.Name -eq $_.Value } | Select-Object -ExpandProperty Name
                foreach ($el in $ToRemove) {
                    $Entities_Before[$k].Remove($el)
                }
            }
            [PSCustomObject]@{
                ComputerName       = $server.ComputerName
                InstanceName       = $server.ServiceName
                SqlInstance        = $server.DomainInstanceName
                Database           = $db
                DBN                = $Entities_Before['DBN']
                DatabaseRenames    = ($Entities_Before['DBN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FGN                = $Entities_Before['FGN']
                FileGroupsRenames  = ($Entities_Before['FGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                LGN                = $Entities_Before['LGN']
                LogicalNameRenames = ($Entities_Before['LGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FNN                = $Entities_Before['FNN']
                FileNameRenames    = ($Entities_Before['FNN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                PendingRenames     = $Final_Renames
                Status             = $Status
            } | Select-DefaultView -ExcludeProperty DatabaseRenames, FileGroupsRenames, LogicalNameRenames, FileNameRenames
        }
        #endregion db loop
    }

    @{ __w3081State = @{ interrupted = (Test-FunctionInterrupt); Final_Renames = $Final_Renames; dirfiles = $dirfiles; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($PSCmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllDatabases $DatabaseName $FileGroupName $LogicalName $FileName $ReplaceBefore $Force $Move $SetOffline $Preview $InputObject $EnableException $__state $__hopInterrupted $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
