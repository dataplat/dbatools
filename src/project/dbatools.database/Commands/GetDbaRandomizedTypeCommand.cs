#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists available data types and subtypes for generating realistic test data during database masking operations
/// </summary>
/// <remarks>
/// Returns all available randomizer types and subtypes that can be used with Get-DbaRandomizedValue for data masking and test data generation. These types include realistic data patterns like Person names, Address components, Finance data, Internet values, and Random data types. This command helps you discover what fake data options are available when building data masking rules or generating test datasets for non-production environments.
/// </remarks>
/// <example><code>Get-DbaRandomizedType</code><para>Get all the types and subtypes</para></example>
/// <example><code>Get-DbaRandomizedType -Pattern "Addr"</code><para>Find all the types and sub types based on a pattern</para></example>
/// <example><code>Get-DbaRandomizedType -RandomizedType Person</code><para>Find all the sub types for Person</para></example>
/// <example><code>Get-DbaRandomizedType -RandomizedSubType LastName</code><para>Get all the types and subtypes that known by "LastName"</para></example>
[Cmdlet(VerbsCommon.Get, "DbaRandomizedType")]
public sealed class GetDbaRandomizedTypeCommand : DbaBaseCmdlet
{
    /// <summary>
    /// Filters results to specific main data categories for realistic test data generation.
    /// Use this when you need to focus on particular data types like Person, Address, Finance, Internet, or Random data.
    /// Available types include Address, Commerce, Company, Database, Date, Finance, Hacker, Image, Internet, Lorem, Name, Person, Phone, Random, System, and more.
    /// </summary>
    [Parameter(Position = 0)]
    public string[]? RandomizedType { get; set; }

    /// <summary>
    /// Filters results to specific data subtypes within the main categories for precise data masking scenarios.
    /// Use this when you need exact data patterns like FirstName, LastName, Email, CreditCardNumber, or ZipCode.
    /// Subtypes provide granular control over the fake data generation for targeted column masking.
    /// </summary>
    [Parameter(Position = 1)]
    public string[]? RandomizedSubType { get; set; }

    /// <summary>
    /// Searches both main types and subtypes using pattern matching to find relevant data generators.
    /// Use this when you're unsure of exact type names or want to discover related options like searching 'Addr' to find Address-related types.
    /// Supports wildcard matching against both Type and SubType columns for flexible discovery.
    /// </summary>
    [Parameter(Position = 2)]
    public string? Pattern { get; set; }

    private List<NativeRandomizerType> _types = new();

    protected override void BeginProcessing()
    {
        try
        {
            _types = NativeRandomizerCatalog.Read();
        }
        catch (Exception)
        {
            // The pinned begin catch has no -Continue and no ErrorRecord argument.
            StopFunction("Could not import randomized types");
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        IEnumerable<NativeRandomizerType> selected = _types;
        if (!string.IsNullOrEmpty(Pattern))
        {
            List<NativeRandomizerType> matches = new();
            // Preserve the two Where-Object passes before the inclusion filters.
            AddMatches(matches, row => row.Type);
            AddMatches(matches, row => row.SubType);
            selected = matches;
        }
        if (LanguagePrimitives.IsTrue(RandomizedType))
            selected = selected.Where(row => NativeDatabaseSelection.ContainsName(RandomizedType, row.Type));
        if (LanguagePrimitives.IsTrue(RandomizedSubType))
            selected = selected.Where(row => NativeDatabaseSelection.ContainsName(RandomizedSubType, row.SubType));

        // Select-Object -Unique compares all three projected properties case-sensitively.
        foreach (NativeRandomizerType row in selected
            .GroupBy(row => new { row.Type, row.SubType, row.RequiredParameter })
            .Select(group => group.First())
            .OrderBy(row => row.Type, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(row => row.SubType, StringComparer.CurrentCultureIgnoreCase))
        {
            CancellationToken.ThrowIfCancellationRequested();
            WriteObject(Project(row, true));
        }
    }

    private void AddMatches(List<NativeRandomizerType> matches, Func<NativeRandomizerType, string> value)
    {
        foreach (NativeRandomizerType row in _types)
        {
            CancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (Regex.IsMatch(value(row), Pattern!, RegexOptions.IgnoreCase))
                    matches.Add(row);
            }
            catch (ArgumentException exception)
            {
                // Where-Object catches the regex argument fault once per input row.
                string message = string.Format(CultureInfo.CurrentCulture,
                    "The argument to operator '{0}' is not valid: {1}.", "Imatch", exception.Message);
                PSArgumentException argumentFault = new(message, "BinaryOperator");
                WriteError(new ErrorRecord(argumentFault, "BadOperatorArgument", ErrorCategory.InvalidArgument, Project(row, false)));
            }
        }
    }

    private static PSObject Project(NativeRandomizerType row, bool selected)
    {
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("Type", row.Type));
        output.Properties.Add(new PSNoteProperty("SubType", row.SubType));
        output.Properties.Add(new PSNoteProperty("RequiredParameter", row.RequiredParameter));
        if (selected)
            output.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        return output;
    }
}
