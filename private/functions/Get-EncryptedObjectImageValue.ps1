function Get-EncryptedObjectImageValue {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Returns the raw ciphertext of the requested encrypted objects by reading the pages of
        sys.sysobjvalues directly.

        The definition of a module created WITH ENCRYPTION is stored in the imageval column of
        sys.sysobjvalues. That column can only be selected over a dedicated admin connection, but the pages
        that hold it can be read with DBCC PAGE, which needs sysadmin and no dedicated admin connection.

        EVERY OFFSET AND CONSTANT HERE IS THE ON DISK FORMAT, derived by experiment against live instances
        rather than read from documentation, and a wrong one returns plausible rubbish instead of failing.

        There are two routes to an object's rows, and they differ by orders of magnitude:

        - Seek. sys.sysobjvalues is a clustered index, so the leaf page holding an object's rows is found by
          descending from the index root. That is a handful of page reads whatever the size of the database.
        - Scan. Every page of the rowset is examined. The number of pages tracks every module in the
          database rather than the encrypted ones, so a database with a few thousand modules has thousands
          of pages, and it grows even where nothing is encrypted. Measured on a database of 7,360 modules,
          29 of them encrypted: 9,669 pages to find 29 rows, against 143 page reads by seek.

        The seek is tried first and the scan is the fallback. A seek that lands on the wrong leaf finds no
        rows, which is a loud failure rather than a silent one, but no rows is also what a genuinely absent
        row looks like. So the seek is never allowed to report absence, and anything it cannot answer with
        confidence hands the whole batch to the scan, which has the final say. That is what makes it safe to
        use by default rather than as an opt in: it can make the answer faster but never wronger. One object
        coming back empty abandons the seek for every object, not just that one.

        Off row values are recorded and resolved together at the end rather than descended into as they are
        found, so that the pages of every off row value in every requested object share the same batches.

        The helpers are nested rather than separate private functions because nothing outside this file
        calls them. The two parts that are unit tested from outside, the dump parser and the chunk
        concatenation, are separate functions for that reason and that reason alone.

        This function is used by the following public functions:
        - Invoke-DbaDbDecryptObject

    .PARAMETER Database
        The SMO database object that holds the encrypted objects. All queries run in the context of this database.

    .PARAMETER ObjectId
        The object ids to return the ciphertext for. Rows of any other object are skipped.

    .PARAMETER BatchSize
        How many pages to ask for per command. Defaults to 32. Measured over 200 real pages: the cost per
        page falls steeply up to about 25 and is flat beyond it, so a larger batch buys nothing and only
        makes one command return several megabytes of text.

    .PARAMETER ForceScan
        Skips the seek and uses the page scan. The two routes share almost no code below the row parse, so
        running both and requiring the same answer is the strongest check available that the seek is finding
        the right rows rather than plausible ones. This switch exists for that comparison.

    .PARAMETER ForceChainWalk
        Skips the seek and the page list and walks the page chain instead, which is the route taken on an
        instance without sys.dm_db_database_page_allocations. Nothing reaches that route by accident on any
        instance from SQL Server 2012 onwards, so without this switch the fallback that the 2005 support
        rests on would never be exercised at all. Like ForceScan, this exists so the routes can be compared.

    .NOTES
        Tags: Encryption, Decrypt
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Get-EncryptedObjectImageValue -Database $db -ObjectId 1253579504

        Returns one object per sys.sysobjvalues row that holds ciphertext of object 1253579504.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Database,
        [Parameter(Mandatory)]
        [int[]]$ObjectId,
        [int]$BatchSize = 32,
        [switch]$ForceScan,
        [switch]$ForceChainWalk
    )

    $pageSize = 8192

    # Rowset id of sys.sysobjvalues. It is a system base table, so this is the same in every database.
    $sysobjvaluesContainerId = 281474980642816

    # Page header fields. m_type is the only trustworthy statement of what a page is, because the DMV that
    # lists pages has been measured omitting pages outright. m_nextPage holds a 4 byte page id followed by a
    # 2 byte file id, and m_slotCnt is the number of slots.
    $pageTypeOffset = 1
    $pageTypeData = 1
    $pageTypeIndex = 2
    $nextPageOffset = 16
    $slotCountOffset = 22

    # Index record of the clustered index, 20 bytes:
    #   [status 1][valclass 1][objid 4][subobjid 4][valnum 4][childPage 4][childFile 2]
    # The key is (valclass, objid, subobjid, valnum) and each entry's key is the minimum key of the page it
    # points at, verified against rows read over a dedicated admin connection.
    $indexRecordSize = 20
    $indexKeyValueClassOffset = 1
    $indexKeyObjectIdOffset = 2
    $indexChildPageOffset = 14
    $indexChildFileOffset = 18

    # Layout of the in row blob root and of a blob record.
    $lobRootHeaderSize = 12
    $lobLinkSize = 12
    $blobTypeOffset = 12
    $blobTypeData = 3
    $blobTypeInternal = 2
    $blobDataOffset = 14
    $internalEntryCountOffset = 16
    $internalEntriesOffset = 20
    $internalEntrySize = 16

    # valclass 1 marks the rows that hold a module definition.
    $moduleValueClass = 1

    # The extent checks below add a length read straight off the page to an offset. In PowerShell an Int32
    # sum that overflows promotes to Double rather than wrapping, so a corrupt length cannot come out
    # negative and pass a check it should fail. The same arithmetic in C# needs an explicit 64 bit cast.

    # Bounds. Each one exists because the thing it bounds follows pointers read out of page bytes, so bytes
    # that are not what they are taken for can point in a circle.
    $maximumSeekDepth = 16
    $maximumForwardPage = 64
    $maximumPageListRound = 8
    $maximumLobDepth = 32

    function Get-PageImage {
        <#
            Returns the raw image of one or more pages, keyed "fileId:pageId".

            Several pages go in one command, because a page costs a round trip and returns only about 39 KB
            of hex, so the round trip is what the time goes on. Every page comes back as its own result set
            carrying its own m_pageId, so each image is stored under the identity the server reported rather
            than the position it arrived in, which makes a mismatch impossible to mistake for data.

            Soft mode lets a page that will not dump be absent instead of throwing. The blob walk uses it,
            because there a missing page is attributed to the one object it belongs to and fails that object
            alone, where throwing would lose every object being resolved in the batch.
        #>
        param(
            [Parameter(Mandatory)]
            [object[]]$Page,
            [switch]$Soft
        )

        # A closing bracket inside the name has to be doubled up to stay inside the quoting, because the
        # name is spliced into DBCC text rather than passed as a parameter.
        $escapedDatabase = $Database.Name -replace "\]", "]]"
        $pageImage = New-Object System.Collections.Hashtable

        # De-duplicated: several blob nodes routinely share a page at different slots.
        $requested = @()
        $seen = New-Object System.Collections.Hashtable
        foreach ($item in $Page) {
            $key = "$([int]$item.FileId):$([int]$item.PageId)"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $requested += $item
            }
        }

        for ($batchStart = 0; $batchStart -lt $requested.Count; $batchStart += $BatchSize) {
            $batchEnd = [Math]::Min($batchStart + $BatchSize, $requested.Count) - 1
            $batch = @($requested[$batchStart..$batchEnd])

            $commandText = ""
            foreach ($item in $batch) {
                $commandText += "DBCC PAGE([$escapedDatabase], $([int]$item.FileId), $([int]$item.PageId), 2) WITH TABLERESULTS;`n"
            }

            foreach ($table in $Database.ExecuteWithResults($commandText).Tables) {
                $identityRow = @($table | Where-Object Field -eq "m_pageId")
                if ($identityRow.Count -eq 0) {
                    continue
                }
                $identity = [regex]::Match([string]$identityRow[0].VALUE, "\((\d+):(-?\d+)\)")
                if (-not $identity.Success) {
                    continue
                }
                $identityKey = "$([int]$identity.Groups[1].Value):$([int]$identity.Groups[2].Value)"
                if ($pageImage.ContainsKey($identityKey)) {
                    continue
                }

                # Collected in one pass rather than by appending, because appending copies the whole array
                # every time and a page is roughly 410 lines.
                $dumpLine = @(
                    foreach ($row in $table.Rows) {
                        if ($row["Object"] -like "Memory Dump*") {
                            [string]$row["VALUE"]
                        }
                    }
                )

                # In soft mode a dump that will not parse is left absent, exactly as a page that did not
                # come back at all is, so the caller faults the one object it belongs to. Letting the parse
                # failure escape would isolate a missing page but not a malformed one.
                try {
                    $pageImage[$identityKey] = ConvertFrom-DbccPageDump -DumpLine $dumpLine -PageSize $pageSize
                } catch {
                    if (-not $Soft) {
                        throw "Could not read page ($identityKey) of database $($Database.Name). $($PSItem.Exception.Message)"
                    }
                    Write-Message -Level Verbose -Message "The dump of page ($identityKey) in database $($Database.Name) could not be parsed. $($PSItem.Exception.Message)"
                }
            }

            # A DBCC error for one page arrives as a message rather than an exception, so it would otherwise
            # be one result set fewer, and a page missing from a scan or a blob reassembly is silent
            # corruption rather than a visible failure.
            if (-not $Soft) {
                foreach ($item in $batch) {
                    $key = "$([int]$item.FileId):$([int]$item.PageId)"
                    if (-not $pageImage.ContainsKey($key)) {
                        throw "DBCC PAGE did not return page ($key) of database $($Database.Name)."
                    }
                }
            }
        }

        return $pageImage
    }

    function Get-RowFromPage {
        <#
            Parses every row on one data page, whatever object it belongs to and whatever its valclass,
            because both routes need more than the rows they are looking for.

            Row layout, offsets relative to the record:
              [status 2][fixedLength 2][valclass 1][objid 4][subobjid 4] ... fixed columns ...
              [columnCount 2 @ fixedLength][null bitmap][variable count 2][offset array]

            The ids are read signed, because an object id uses the full 32 bit range and SQL Server reports
            it signed as well. Reading them through a checked conversion threw on ids above int.MaxValue and
            silently skipped those rows.

            Everything past the fixed columns is walked using lengths read out of the row itself, so a row
            whose bytes are not the layout expected is skipped rather than trusted, and must never throw:
            this runs inside both routes, so one exception would lose every object in the batch.
        #>
        param(
            [Parameter(Mandatory)]
            [byte[]]$Page
        )

        $slotCount = [int][BitConverter]::ToUInt16($Page, $slotCountOffset)
        for ($slot = 0; $slot -lt $slotCount; $slot++) {
            $recordOffset = [int][BitConverter]::ToUInt16($Page, $pageSize - 2 - $slot * 2)
            if ($recordOffset -le 0 -or ($recordOffset + 17) -ge $pageSize) {
                continue
            }

            $fixedLength = [int][BitConverter]::ToUInt16($Page, $recordOffset + 2)
            $valueClass = $Page[$recordOffset + 4]
            $rowObjectId = [BitConverter]::ToInt32($Page, $recordOffset + 5)
            $subObjectId = [BitConverter]::ToInt32($Page, $recordOffset + 9)

            $columnCountOffset = $recordOffset + $fixedLength
            if ($fixedLength -lt 4 -or ($columnCountOffset + 2) -gt $pageSize) {
                continue
            }

            $columnCount = [int][BitConverter]::ToUInt16($Page, $columnCountOffset)
            $nullBitmapSize = [int][Math]::Floor(($columnCount + 7) / 8)
            $variableCountOffset = $columnCountOffset + 2 + $nullBitmapSize
            if (($variableCountOffset + 2) -gt $pageSize) {
                continue
            }

            $variableCount = [int][BitConverter]::ToUInt16($Page, $variableCountOffset)
            $offsetArray = $variableCountOffset + 2
            if ($variableCount -lt 1 -or ($offsetArray + $variableCount * 2) -gt $pageSize) {
                continue
            }

            # imageval is the last variable length column, so its end offset is the last entry of the offset
            # array and its start is the entry before. The single column fallback is the start of the
            # variable region, and the offset array position is absolute while the stored offsets are row
            # relative, so the record offset is taken back off to match them.
            $columnEnd = [int][BitConverter]::ToUInt16($Page, $offsetArray + ($variableCount - 1) * 2)
            if ($variableCount -ge 2) {
                $previousEnd = [int][BitConverter]::ToUInt16($Page, $offsetArray + ($variableCount - 2) * 2)
            } else {
                $previousEnd = $offsetArray + $variableCount * 2 - $recordOffset
            }

            # The high bit of the end offset marks a value held off row.
            $isLob = ($columnEnd -band 0x8000) -ne 0
            $columnStart = $previousEnd -band 0x7FFF
            $columnEndOffset = $columnEnd -band 0x7FFF
            if ($columnStart -gt $columnEndOffset -or ($recordOffset + $columnEndOffset) -gt $pageSize) {
                continue
            }

            $columnLength = $columnEndOffset - $columnStart
            $columnValue = New-Object byte[] $columnLength
            [Array]::Copy($Page, $recordOffset + $columnStart, $columnValue, 0, $columnLength)

            [PSCustomObject]@{
                ValueClass = [int]$valueClass
                ObjectId   = $rowObjectId
                ColId      = $subObjectId
                IsLob      = $isLob
                Value      = $columnValue
            }
        }
    }

    function Test-PagePastObject {
        <#
            True when a page holds a row sorting after every possible row of one object, so no later page
            can hold one either and the forward walk can stop.

            TESTING ANY SLOT IS CORRECT, and it reads as though it ought to be the highest key on the page.
            Leaf pages are in key order, so every key here is at or below every key on the next page. If any
            slot is past the target then this page's maximum is past it, the target's contiguous range has
            already ended, and its rows were harvested from this page before this was asked. Slot order
            within the page is irrelevant, and comparing only the highest key is equivalent, not safer.

            This reads valclass and objid straight out of the fixed part, deliberately, so that it can judge
            a row the full parse would reject. A page whose rows all failed that parse would otherwise never
            trip the stop and the walk would carry on past the end of the range.
        #>
        param(
            [Parameter(Mandatory)]
            [byte[]]$Page,
            [Parameter(Mandatory)]
            [int]$TargetObjectId
        )

        $slotCount = [int][BitConverter]::ToUInt16($Page, $slotCountOffset)
        for ($slot = 0; $slot -lt $slotCount; $slot++) {
            $recordOffset = [int][BitConverter]::ToUInt16($Page, $pageSize - 2 - $slot * 2)
            if ($recordOffset -le 0 -or ($recordOffset + 17) -ge $pageSize) {
                continue
            }

            $valueClass = [int]$Page[$recordOffset + 4]
            $rowObjectId = [BitConverter]::ToInt32($Page, $recordOffset + 5)

            if ($valueClass -gt $moduleValueClass) {
                return $true
            }
            if ($valueClass -eq $moduleValueClass -and $rowObjectId -gt $TargetObjectId) {
                return $true
            }
        }

        return $false
    }

    function Get-LeafPageForObject {
        <#
            Descends the clustered index to the leaf page that should hold (valclass 1, objectId), choosing
            at each level the last entry whose key is not past the target. Returns nothing when the descent
            cannot be trusted, which sends the caller to the scan.

            TWO THINGS MAKE THIS CORRECT and getting either wrong sends every object to the wrong leaf,
            which looks exactly like a decode failure:

            - Compare the whole key, in order, and valclass leads it. A module definition is valclass 1
              while the bulk of sys.sysobjvalues is valclass 60, so every module row sorts into the leftmost
              subtree. Comparing the object id alone picks the last entry by object id and sends every target
              to the final leaf.
            - The leftmost entry of an index page has no meaningful stored key. It decodes to whatever was
              left in those bytes, which reads as a plausible key, and it covers everything below the key of
              the entry after it. It has to be treated as negative infinity.

            Only the leading two key columns are needed, because the target is the first key the object
            could have, (1, objectId, 0, 0), so an entry with the same valclass and object id is already at
            or past it.
        #>
        param(
            [Parameter(Mandatory)]
            $RootPage,
            [Parameter(Mandatory)]
            [int]$TargetObjectId
        )

        $currentPage = $RootPage
        $indexPageRead = 0

        for ($depth = 0; $depth -lt $maximumSeekDepth; $depth++) {
            $currentKey = "$([int]$currentPage.FileId):$([int]$currentPage.PageId)"

            # The upper levels of the index are the same handful of pages for every object, so without a
            # cache a run over many objects re-reads the root once per object. The cache holds index pages
            # only, which is a few pages whatever the size of the database, and it is discarded with this
            # invocation so no page is ever read from a stale image.
            if ($indexPageCache.ContainsKey($currentKey)) {
                $page = $indexPageCache[$currentKey]
            } else {
                $pageRef = @(
                    [PSCustomObject]@{
                        FileId = [int]$currentPage.FileId
                        PageId = [int]$currentPage.PageId
                    }
                )
                $page = (Get-PageImage -Page $pageRef)[$currentKey]
                $indexPageRead++

                # Only an index page is worth keeping. A leaf is read once per object at most and holding
                # leaves would grow with the size of the rowset.
                if ($page[$pageTypeOffset] -eq $pageTypeIndex) {
                    $indexPageCache[$currentKey] = $page
                }
            }

            $pageType = $page[$pageTypeOffset]
            if ($pageType -eq $pageTypeData) {
                return [PSCustomObject]@{
                    FileId        = [int]$currentPage.FileId
                    PageId        = [int]$currentPage.PageId
                    IndexPageRead = $indexPageRead
                }
            }

            if ($pageType -ne $pageTypeIndex) {
                Write-Message -Level Verbose -Message "Page ($([int]$currentPage.FileId):$([int]$currentPage.PageId)) of database $($Database.Name) is type $pageType rather than an index or data page, so the seek is abandoned."
                return
            }

            $chosen = $null
            $slotCount = [int][BitConverter]::ToUInt16($page, $slotCountOffset)
            for ($slot = 0; $slot -lt $slotCount; $slot++) {
                $recordOffset = [int][BitConverter]::ToUInt16($page, $pageSize - 2 - $slot * 2)
                if ($recordOffset -le 0 -or ($recordOffset + $indexRecordSize) -gt $pageSize) {
                    continue
                }

                $childEntry = [PSCustomObject]@{
                    FileId = [int][BitConverter]::ToUInt16($page, $recordOffset + $indexChildFileOffset)
                    PageId = [BitConverter]::ToInt32($page, $recordOffset + $indexChildPageOffset)
                }

                if ($slot -eq 0) {
                    $chosen = $childEntry
                    continue
                }

                $keyValueClass = [int]$page[$recordOffset + $indexKeyValueClassOffset]
                $keyObjectId = [BitConverter]::ToInt32($page, $recordOffset + $indexKeyObjectIdOffset)

                if ($keyValueClass -lt $moduleValueClass) {
                    $chosen = $childEntry
                    continue
                }

                # Strictly less than, not less than or equal. The target is the object's FIRST key,
                # (1, objid, 0, 0), so an entry whose minimum key is (1, objid, subobjid > 0, ...) is
                # already past the target even though its (valclass, objid) prefix matches. Choosing it
                # would land the descent on a LATER leaf, and because the walk from there only follows
                # m_nextPage forward, a chunk of the definition on the earlier page would never be seen -
                # silently, as rows are still found and every other check passes. Stopping here instead
                # lands on the page before the object's first row and the forward walk collects from
                # there, which costs at most one extra page read.
                if ($keyValueClass -eq $moduleValueClass -and $keyObjectId -lt $TargetObjectId) {
                    $chosen = $childEntry
                    continue
                }

                # The entries are in key order, so everything after this one is past the target too.
                break
            }

            if ($null -eq $chosen) {
                Write-Message -Level Verbose -Message "No child entry of page ($([int]$currentPage.FileId):$([int]$currentPage.PageId)) in database $($Database.Name) covers object $TargetObjectId, so the seek is abandoned."
                return
            }

            $currentPage = $chosen
        }

        Write-Message -Level Verbose -Message "The index of sys.sysobjvalues in database $($Database.Name) is deeper than $maximumSeekDepth levels, so the seek is abandoned."
    }

    function Add-NodePayload {
        <#
            Writes the payload of a resolved blob node, and everything below it, into a stream in depth
            first order. The tree is read breadth first so a level's pages can be fetched together, but the
            ciphertext is only correct when the leaves are concatenated depth first, and keeping those two
            apart is what makes the batched read safe.
        #>
        param(
            [Parameter(Mandatory)]
            $Node,
            [Parameter(Mandatory)]
            $Stream
        )

        if ($null -ne $Node.Payload) {
            $Stream.Write($Node.Payload, 0, $Node.Payload.Length)
            return
        }
        if ($null -eq $Node.Children) {
            return
        }
        foreach ($child in $Node.Children) {
            Add-NodePayload -Node $child -Stream $Stream
        }
    }

    function Get-LobData {
        <#
            Resolves off row values into their complete ciphertext, many at once.

            The in row bytes are a LARGE_ROOT_YUKON root: a 12 byte header then 12 byte links of cumulative
            length, page id, file id and slot id. Every link points at a blob record whose 14 byte header
            carries its type at offset 12: type 3 is a data leaf whose payload is the record length minus
            the header, type 2 an internal node with its entry count at offset 16 and 16 byte entries from
            offset 20.

            Walked breadth first, one level at a time, so every page a level needs goes in a few commands. A
            depth first walk cannot batch, because a child's page id is only known when it is about to be
            read. Taking every value together means the batches span objects as well as levels.

            THE THING TO GET RIGHT is that the ciphertext is assembled depth first, from the finished tree,
            rather than appended as pages arrive. Getting that wrong produces ciphertext of exactly the
            right length that decrypts to plausible rubbish, which only a byte for byte comparison catches.

            A page that will not dump, a record that is not the shape expected, or a value that reassembles
            to no bytes at all faults only the value it belongs to, which is then absent from the result.
            Off row storage was used because there was data that would not fit in row, so nothing coming
            back means a root or a leaf did not resolve.
        #>
        param(
            [Parameter(Mandatory)]
            [object[]]$Root
        )

        $faulted = New-Object System.Collections.Hashtable
        $rootNode = New-Object System.Collections.Hashtable
        $currentLevel = @()

        foreach ($item in $Root) {
            $rootBytes = $item.LobRoot
            $linkCount = [int][Math]::Floor(($rootBytes.Length - $lobRootHeaderSize) / $lobLinkSize)
            if ($linkCount -lt 0) {
                Write-Message -Level Verbose -Message "The blob root of value $($item.Key) in database $($Database.Name) is only $($rootBytes.Length) bytes, which is shorter than its own header."
                $faulted[$item.Key] = $true
                $rootNode[$item.Key] = @()
                continue
            }

            # Built in one pass and added to the level once, because appending per link copies both arrays
            # every time and a root can hold hundreds of links.
            $childNode = @(
                for ($link = 0; $link -lt $linkCount; $link++) {
                    $linkOffset = $lobRootHeaderSize + $link * $lobLinkSize
                    [PSCustomObject]@{
                        FileId   = [int][BitConverter]::ToUInt16($rootBytes, $linkOffset + 8)
                        PageId   = [BitConverter]::ToInt32($rootBytes, $linkOffset + 4)
                        SlotId   = [int][BitConverter]::ToUInt16($rootBytes, $linkOffset + 10)
                        Owner    = $item.Key
                        Payload  = $null
                        Children = $null
                    }
                }
            )

            $currentLevel += $childNode
            $rootNode[$item.Key] = $childNode
        }

        $depth = 0
        while ($currentLevel.Count -gt 0) {
            $depth++
            if ($depth -gt $maximumLobDepth) {
                throw "The blob tree in database $($Database.Name) is deeper than $maximumLobDepth levels, which means its pointers do not terminate."
            }

            $nextLevel = @()

            # Each batch is discarded once its records are parsed, so the page images of a large definition
            # are never all held at once.
            for ($batchStart = 0; $batchStart -lt $currentLevel.Count; $batchStart += $BatchSize) {
                $batchEnd = [Math]::Min($batchStart + $BatchSize, $currentLevel.Count) - 1
                $batch = @($currentLevel[$batchStart..$batchEnd])
                $pageImage = Get-PageImage -Page $batch -Soft

                foreach ($node in $batch) {
                    # A sibling under the same owner may already have faulted it, so its subtree is moot.
                    if ($faulted.ContainsKey($node.Owner)) {
                        continue
                    }

                    $nodeKey = "$($node.FileId):$($node.PageId)"
                    if (-not $pageImage.ContainsKey($nodeKey)) {
                        Write-Message -Level Verbose -Message "Page ($nodeKey) of database $($Database.Name) did not dump, so the off row value $($node.Owner) cannot be reassembled."
                        $faulted[$node.Owner] = $true
                        continue
                    }
                    $page = $pageImage[$nodeKey]

                    $recordOffset = [int][BitConverter]::ToUInt16($page, $pageSize - 2 - $node.SlotId * 2)
                    if ($recordOffset -le 0 -or ($recordOffset + $internalEntriesOffset) -gt $pageSize) {
                        Write-Message -Level Verbose -Message "Bad blob record pointer ($nodeKey) slot $($node.SlotId) in database $($Database.Name), record offset $recordOffset."
                        $faulted[$node.Owner] = $true
                        continue
                    }

                    $recordType = [int][BitConverter]::ToUInt16($page, $recordOffset + $blobTypeOffset)

                    if ($recordType -eq $blobTypeData) {
                        $recordLength = [BitConverter]::ToInt32($page, $recordOffset + 2)
                        $dataLength = $recordLength - $blobDataOffset
                        if ($dataLength -lt 0 -or ($recordOffset + $blobDataOffset + $dataLength) -gt $pageSize) {
                            Write-Message -Level Verbose -Message "Bad blob data leaf ($nodeKey) slot $($node.SlotId) in database $($Database.Name), record length $recordLength."
                            $faulted[$node.Owner] = $true
                            continue
                        }

                        $leafData = New-Object byte[] $dataLength
                        [Array]::Copy($page, $recordOffset + $blobDataOffset, $leafData, 0, $dataLength)
                        $node.Payload = $leafData
                    } elseif ($recordType -eq $blobTypeInternal) {
                        $entryCount = [BitConverter]::ToInt32($page, $recordOffset + $internalEntryCountOffset)
                        if ($entryCount -lt 0 -or ($recordOffset + $internalEntriesOffset + $entryCount * $internalEntrySize) -gt $pageSize) {
                            Write-Message -Level Verbose -Message "Bad blob internal node ($nodeKey) slot $($node.SlotId) in database $($Database.Name), entry count $entryCount."
                            $faulted[$node.Owner] = $true
                            continue
                        }

                        $childNode = @(
                            for ($entry = 0; $entry -lt $entryCount; $entry++) {
                                $entryOffset = $recordOffset + $internalEntriesOffset + $entry * $internalEntrySize
                                [PSCustomObject]@{
                                    FileId   = [int][BitConverter]::ToUInt16($page, $entryOffset + 12)
                                    PageId   = [BitConverter]::ToInt32($page, $entryOffset + 8)
                                    SlotId   = [int][BitConverter]::ToUInt16($page, $entryOffset + 14)
                                    Owner    = $node.Owner
                                    Payload  = $null
                                    Children = $null
                                }
                            }
                        )

                        $nextLevel += $childNode
                        $node.Children = $childNode
                    } else {
                        Write-Message -Level Verbose -Message "Unknown blob record type $recordType at ($nodeKey) slot $($node.SlotId) in database $($Database.Name)."
                        $faulted[$node.Owner] = $true
                    }
                }

                $pageImage = $null
            }

            $currentLevel = $nextLevel
        }

        $cipher = New-Object System.Collections.Hashtable
        foreach ($item in $Root) {
            if ($faulted.ContainsKey($item.Key)) {
                continue
            }

            $lobStream = New-Object System.IO.MemoryStream
            try {
                foreach ($node in $rootNode[$item.Key]) {
                    Add-NodePayload -Node $node -Stream $lobStream
                }
                $value = $lobStream.ToArray()
            } finally {
                $lobStream.Dispose()
            }

            if ($value.Length -eq 0) {
                Write-Message -Level Verbose -Message "The off row value $($item.Key) in database $($Database.Name) reassembled to no bytes, so it is treated as unresolved."
                continue
            }

            $cipher[$item.Key] = $value
        }

        return $cipher
    }

    # ---- identities, refused before any page is read ----------------------------------------------

    $requestedObjectId = @($ObjectId | Sort-Object -Unique)

    # Two separate refusals here, and each catches what the other cannot.
    #
    # sys.sysobjvalues holds the text of every module, not only the encrypted ones. Pointed at a plain
    # module the reader would find its row, XOR plaintext against a keystream and return rubbish of exactly
    # the right length with nothing else to show it was wrong. A NULL means the property could not be
    # evaluated, which is not the same as a no, so only an explicit 0 is refused on that test.
    #
    # A T-SQL module also has to exist at all, which is a fact rather than a judgement. SMO reports
    # IsEncrypted as true for a CLR function, and a CLR function has no T-SQL body to encrypt, so asking
    # for one sends this reader hunting rows that cannot exist. OBJECTPROPERTY cannot save it: for a CLR
    # module the answer is NULL, which is the case that is deliberately allowed through. Finding no rows
    # then reads as "the seek could not answer" and hands the whole batch to a full page scan, so three CLR
    # functions in a database turned a few page reads into nine thousand. A module with no row in
    # sys.sql_modules holds nothing this reader can decrypt, so it is refused outright. The reference
    # implementation avoids this by joining sys.sql_modules when it picks candidates in the first place.
    $queryIsEncrypted = @"
SELECT o.object_id AS ObjectId,
       OBJECTPROPERTY(o.object_id, 'IsEncrypted') AS IsEncrypted,
       CASE WHEN m.object_id IS NULL THEN 0 ELSE 1 END AS HasSqlModule
FROM sys.objects AS o
LEFT JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE o.object_id IN ($($requestedObjectId -join ", "))
"@

    $wantedObjectId = New-Object System.Collections.Hashtable
    foreach ($id in $requestedObjectId) {
        $wantedObjectId[$id] = $true
    }
    foreach ($row in @($Database.Query($queryIsEncrypted))) {
        if ([int]$row.HasSqlModule -eq 0) {
            Write-Message -Level Verbose -Message "Object $($row.ObjectId) in database $($Database.Name) has no T-SQL module, so there is nothing here to decrypt and it is skipped."
            $wantedObjectId.Remove([int]$row.ObjectId)
            continue
        }

        if ($row.IsEncrypted -isnot [DBNull] -and [int]$row.IsEncrypted -eq 0) {
            Write-Message -Level Verbose -Message "Object $($row.ObjectId) in database $($Database.Name) is not encrypted, so it is skipped."
            $wantedObjectId.Remove([int]$row.ObjectId)
        }
    }
    if ($wantedObjectId.Count -eq 0) {
        return
    }

    # ---- the allocation unit, which both routes need ----------------------------------------------

    $queryAllocationUnit = @"
SELECT au.allocation_unit_id AS AllocationUnitId, au.first_page AS FirstPage, au.root_page AS RootPage, au.data_pages AS DataPages
FROM sys.system_internals_allocation_units AS au
WHERE au.container_id = $sysobjvaluesContainerId
AND au.type = 1
"@

    $allocationUnit = @($Database.Query($queryAllocationUnit))
    if ($allocationUnit.Count -eq 0 -or $allocationUnit[0].FirstPage -isnot [byte[]]) {
        throw "Could not find the in row allocation unit of sys.sysobjvalues in database $($Database.Name)."
    }

    # first_page and root_page are both binary(6) of a 4 byte page id then a 2 byte file id, so they read
    # back to front from the familiar form. first_page is the head of the leaf level and root_page the top
    # of the index, and using one where the other belongs walks the wrong level.
    $firstPage = $allocationUnit[0].FirstPage
    $firstPageEntry = [PSCustomObject]@{
        FileId = [int][BitConverter]::ToUInt16($firstPage, 4)
        PageId = [BitConverter]::ToInt32($firstPage, 0)
    }

    $rootPageEntry = $null
    if ($allocationUnit[0].RootPage -is [byte[]]) {
        $rootPageEntry = [PSCustomObject]@{
            FileId = [int][BitConverter]::ToUInt16($allocationUnit[0].RootPage, 4)
            PageId = [BitConverter]::ToInt32($allocationUnit[0].RootPage, 0)
        }
    }

    $expectedPage = 0
    if ($allocationUnit[0].DataPages -isnot [DBNull]) {
        $expectedPage = [int]$allocationUnit[0].DataPages
    }

    $chunkIndex = 0
    $chunk = $null

    # ---- route one: seek the index for each object ------------------------------------------------

    if (-not $ForceScan -and -not $ForceChainWalk -and $null -ne $rootPageEntry -and $rootPageEntry.PageId -ne 0) {
        $seekChunk = @()
        $seekAbandoned = $false
        $indexPageRead = 0
        $leafPageRead = 0
        $indexPageCache = New-Object System.Collections.Hashtable

        foreach ($targetObjectId in @($wantedObjectId.Keys | Sort-Object)) {
            # The descent and the forward walk are both inside this try, deliberately. The seek's contract
            # is that it is never wronger than the scan, only faster, so any surprise here has to hand over
            # to the scan rather than fail the batch. That includes a page that will not dump: the same page
            # may well read fine as part of a scan, and even if it does not, it is the scan that says so.
            $objectChunk = $null
            try {
                $leaf = Get-LeafPageForObject -RootPage $rootPageEntry -TargetObjectId $targetObjectId
                if ($null -eq $leaf) {
                    $seekAbandoned = $true
                    break
                }
                $indexPageRead += $leaf.IndexPageRead

                $visitedLeaf = New-Object System.Collections.Hashtable
                $seenColId = New-Object System.Collections.Hashtable
                $harvested = @()
                $currentLeaf = [PSCustomObject]@{
                    FileId = [int]$leaf.FileId
                    PageId = [int]$leaf.PageId
                }

                for ($forward = 0; $forward -lt $maximumForwardPage; $forward++) {
                    if ($null -eq $currentLeaf -or $currentLeaf.PageId -eq 0) {
                        break
                    }

                    $leafKey = "$($currentLeaf.FileId):$($currentLeaf.PageId)"

                    # A cycle would harvest the same rows again and concatenate a definition into a multiple
                    # of its real length. The page bound alone would not catch that.
                    if ($visitedLeaf.ContainsKey($leafKey)) {
                        Write-Message -Level Verbose -Message "The forward walk of sys.sysobjvalues in database $($Database.Name) revisited page ($leafKey), so the seek is abandoned."
                        $seekAbandoned = $true
                        break
                    }
                    $visitedLeaf[$leafKey] = $true

                    $page = (Get-PageImage -Page @($currentLeaf))[$leafKey]
                    $leafPageRead++

                    if ($page[$pageTypeOffset] -ne $pageTypeData) {
                        break
                    }

                    foreach ($row in (Get-RowFromPage -Page $page)) {
                        if ($row.ValueClass -ne $moduleValueClass -or $row.ObjectId -ne $targetObjectId) {
                            continue
                        }

                        # Each row of an object has a distinct subobjid, and subobjid is the colid the
                        # keystream is built from. A repeat means the same row was harvested twice, and
                        # concatenating it twice gives a definition of the wrong length that still decrypts
                        # to readable text.
                        if ($seenColId.ContainsKey($row.ColId)) {
                            Write-Message -Level Verbose -Message "Object $targetObjectId in database $($Database.Name) yielded colid $($row.ColId) twice, so the seek is abandoned."
                            $seekAbandoned = $true
                            break
                        }
                        $seenColId[$row.ColId] = $true
                        $harvested += $row
                    }

                    if ($seekAbandoned) {
                        break
                    }
                    if (Test-PagePastObject -Page $page -TargetObjectId $targetObjectId) {
                        break
                    }

                    $currentLeaf = [PSCustomObject]@{
                        FileId = [int][BitConverter]::ToUInt16($page, $nextPageOffset + 4)
                        PageId = [BitConverter]::ToInt32($page, $nextPageOffset)
                    }
                }

                if (-not $seekAbandoned) {
                    # Nothing but the requested object may have been collected. The filter above makes this
                    # unreachable, which is why it is worth asserting rather than assuming: if it ever
                    # fires, the alternative is decrypting one module's bytes as another's.
                    $foreign = @($harvested | Where-Object { $PSItem.ObjectId -ne $targetObjectId })
                    if ($foreign.Count -gt 0) {
                        Write-Message -Level Verbose -Message "The forward walk in database $($Database.Name) collected rows for an object other than $targetObjectId, so the seek is abandoned."
                        $seekAbandoned = $true
                    } else {
                        $objectChunk = @(
                            foreach ($row in $harvested) {
                                $chunkIndex++
                                $chunkEntry = [PSCustomObject]@{
                                    Key      = $chunkIndex
                                    ObjectId = $row.ObjectId
                                    ColId    = $row.ColId
                                    Cipher   = $row.Value
                                    LobRoot  = $null
                                }
                                if ($row.IsLob) {
                                    $chunkEntry.Cipher = $null
                                    $chunkEntry.LobRoot = $row.Value
                                }
                                $chunkEntry
                            }
                        )
                    }
                }
            } catch {
                Write-Message -Level Verbose -Message "The seek for object $targetObjectId in database $($Database.Name) could not complete, so the page scan is used instead. $($PSItem.Exception.Message)"
                $seekAbandoned = $true
            }

            if ($seekAbandoned) {
                break
            }

            # Absence is not the seek's to report. The scan decides.
            if ($objectChunk.Count -eq 0) {
                Write-Message -Level Verbose -Message "The seek found no rows for object $targetObjectId in database $($Database.Name), so the page scan settles whether they exist."
                $seekAbandoned = $true
                break
            }

            $seekChunk += $objectChunk
        }

        if ($seekAbandoned) {
            $chunkIndex = 0
        } else {
            Write-Message -Level Verbose -Message "Seeked the index of sys.sysobjvalues in database $($Database.Name) for $($wantedObjectId.Count) objects, reading $indexPageRead index pages and $leafPageRead leaf pages."
            $chunk = $seekChunk
        }
    }

    # ---- route two: scan every page of the rowset -------------------------------------------------

    if ($null -eq $chunk) {
        # Testing for the object tests the thing actually needed rather than using a version number as a
        # proxy for it, so an instance without the DMV for any other reason falls back cleanly.
        $queryDmv = @"
SELECT OBJECT_ID('sys.dm_db_database_page_allocations') AS DmvObjectId
"@
        $dmv = @($Database.Query($queryDmv))
        $dmvPresent = $dmv.Count -ge 1 -and $dmv[0].DmvObjectId -isnot [DBNull] -and $null -ne $dmv[0].DmvObjectId
        if ($ForceChainWalk) {
            $dmvPresent = $false
        }

        $candidate = @()
        if ($dmvPresent) {
            # DETAILED is required. Under LIMITED the page type is left NULL, the filter matches nothing,
            # and every object would read as never having been encrypted.
            $queryDataPage = @"
SELECT allocated_page_file_id AS FileId, allocated_page_page_id AS PageId
FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED')
WHERE allocation_unit_id = $($allocationUnit[0].AllocationUnitId)
AND page_type_desc = 'DATA_PAGE'
"@
            $candidate = @(
                foreach ($row in @($Database.Query($queryDataPage))) {
                    [PSCustomObject]@{
                        FileId = [int]$row.FileId
                        PageId = [int]$row.PageId
                    }
                }
            )

            # An empty list means the DMV did not answer, not that the rowset has no pages.
            if ($candidate.Count -eq 0) {
                Write-Message -Level Verbose -Message "The page list of sys.sysobjvalues came back empty in database $($Database.Name), so the page chain is walked instead."
                $dmvPresent = $false
            }
        }

        # The head of the chain is always a candidate, in case the page list left it out. The leaf level is
        # a linked list, so a set containing first_page and closed under the next pointer is the whole
        # chain, which makes the page list provably complete rather than hopefully complete. The DMV has
        # been measured omitting genuine data pages of the rowset, and a missing page means an object that
        # reads as never having been encrypted. This is also why a page is only parsed as data when its own
        # header says so.
        $candidate += $firstPageEntry

        Write-Message -Level Verbose -Message "Scanning the sys.sysobjvalues pages of database $($Database.Name) using $(if ($dmvPresent) { "the page list" } else { "the page chain" })."

        $maximumPage = $expectedPage * 2 + 1000

        # The two routes reach the same loop with completely different round counts. The page list arrives
        # whole in the first round and needs at most a round or two of gap filling, so a low cap is what
        # catches a set that will not close. The chain walk learns exactly one page per round by design,
        # because a page is what names the next one, so its rounds are bounded by the number of pages
        # instead - which the visited cap below is already the guard for. Holding the chain walk to the page
        # list's cap made it fail on any rowset longer than that many pages, which is nearly all of them.
        $maximumRound = $maximumPage + 1
        if ($dmvPresent) {
            $maximumRound = $maximumPageListRound
        }

        $visited = New-Object System.Collections.Hashtable
        $scanChunk = @()
        $round = 0

        while ($candidate.Count -gt 0) {
            $round++
            if ($round -gt $maximumRound) {
                throw "The page set of sys.sysobjvalues in database $($Database.Name) did not close after $maximumRound rounds, so it is not safe to continue."
            }

            $pending = @(
                foreach ($item in $candidate) {
                    $key = "$($item.FileId):$($item.PageId)"
                    if ($item.PageId -ne 0 -and -not $visited.ContainsKey($key)) {
                        $visited[$key] = $true
                        $item
                    }
                }
            )

            if ($pending.Count -eq 0) {
                break
            }
            if ($visited.Count -gt $maximumPage) {
                throw "Reading sys.sysobjvalues in database $($Database.Name) reached $($visited.Count) pages, well past the $expectedPage it reports, so its page pointers do not terminate."
            }

            # Keyed rather than appended to, because there is one next pointer per page read and appending
            # copies the array every time. Keying also collapses the duplicates that arrive when the page
            # list and the next pointers name the same page.
            $nextCandidate = New-Object System.Collections.Hashtable

            for ($batchStart = 0; $batchStart -lt $pending.Count; $batchStart += $BatchSize) {
                $batchEnd = [Math]::Min($batchStart + $BatchSize, $pending.Count) - 1
                $batch = @($pending[$batchStart..$batchEnd])
                $pageImage = Get-PageImage -Page $batch

                foreach ($item in $batch) {
                    $page = $pageImage["$($item.FileId):$($item.PageId)"]

                    if ($page[$pageTypeOffset] -ne $pageTypeData) {
                        continue
                    }

                    $nextEntry = [PSCustomObject]@{
                        FileId = [int][BitConverter]::ToUInt16($page, $nextPageOffset + 4)
                        PageId = [BitConverter]::ToInt32($page, $nextPageOffset)
                    }
                    $nextCandidate["$($nextEntry.FileId):$($nextEntry.PageId)"] = $nextEntry

                    foreach ($row in (Get-RowFromPage -Page $page)) {
                        if ($row.ValueClass -ne $moduleValueClass -or -not $wantedObjectId.ContainsKey($row.ObjectId)) {
                            continue
                        }

                        $chunkIndex++
                        $chunkEntry = [PSCustomObject]@{
                            Key      = $chunkIndex
                            ObjectId = $row.ObjectId
                            ColId    = $row.ColId
                            Cipher   = $row.Value
                            LobRoot  = $null
                        }
                        if ($row.IsLob) {
                            $chunkEntry.Cipher = $null
                            $chunkEntry.LobRoot = $row.Value
                        }
                        $scanChunk += $chunkEntry
                    }
                }

                $pageImage = $null
            }

            $candidate = @($nextCandidate.Values)
        }

        Write-Message -Level Verbose -Message "Scanned $($visited.Count) pages of sys.sysobjvalues in database $($Database.Name)."
        $chunk = $scanChunk
    }

    # ---- resolve the off row values, then hand back the chunks --------------------------------------

    $deferred = @($chunk | Where-Object { $null -ne $PSItem.LobRoot })
    Write-Message -Level Verbose -Message "Found $($chunk.Count) rows for $($wantedObjectId.Count) objects in database $($Database.Name), $($deferred.Count) of them stored off row."

    if ($deferred.Count -ge 1) {
        $lobCipher = Get-LobData -Root $deferred
        foreach ($chunkEntry in $deferred) {
            if ($lobCipher.ContainsKey($chunkEntry.Key)) {
                $chunkEntry.Cipher = $lobCipher[$chunkEntry.Key]
            }
        }
    }

    # A chunk without ciphertext is an off row value whose blob tree could not be reassembled. It is handed
    # back as it is, with a null cipher, so that the caller can tell the difference between an object with
    # no rows and an object whose body could not be read, and can say so to the user. What must not happen
    # is decrypting it from part of itself, which would return a definition built out of a fragment.
    foreach ($chunkEntry in $chunk) {
        if ($null -eq $chunkEntry.Cipher) {
            Write-Message -Level Verbose -Message "Chunk $($chunkEntry.ColId) of object $($chunkEntry.ObjectId) in database $($Database.Name) has no ciphertext, because its off row body could not be reassembled."
        }

        [PSCustomObject]@{
            ObjectId = $chunkEntry.ObjectId
            ColId    = $chunkEntry.ColId
            Cipher   = $chunkEntry.Cipher
        }
    }
}
