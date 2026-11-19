#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// How Set-DbaSsisEnvironmentVariable turns what the caller asked for into the variables it will
/// act on, and what it says about the names that matched nothing.
/// </summary>
public sealed partial class SetDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// Reports the names the catalog had nothing for, most specific selector first. A broader
    /// selector alongside a narrower one is a scope rather than an ask - a folder that holds
    /// variables other than the named ones is not a missing folder.
    /// </summary>
    private void ReportUnmatchedNames(DbaInstanceParameter instance, List<VariableTarget> resolved)
    {
        if (FilterHelper.IsActive(Variable))
        {
            foreach (string variableName in Variable!)
            {
                if (!resolved.Exists(target => String.Equals(target.Name, variableName, StringComparison.OrdinalIgnoreCase)))
                {
                    StopFunction($"SSIS environment variable {variableName} does not exist{DescribeScope()} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                }
            }
            return;
        }

        if (FilterHelper.IsActive(Environment))
        {
            foreach (string environmentName in Environment!)
            {
                if (!resolved.Exists(target => String.Equals(target.EnvironmentName, environmentName, StringComparison.OrdinalIgnoreCase)))
                {
                    StopFunction($"No SSIS environment variable found in environment {environmentName} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                }
            }
            return;
        }

        foreach (string folderName in Folder ?? Array.Empty<string>())
        {
            if (!resolved.Exists(target => String.Equals(target.FolderName, folderName, StringComparison.OrdinalIgnoreCase)))
            {
                StopFunction($"No SSIS environment variable found in folder {folderName} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
            }
        }
    }

    private string DescribeScope()
    {
        if (FilterHelper.IsActive(Folder) && FilterHelper.IsActive(Environment))
        {
            return $" in {String.Join(", ", Folder!)}\\{String.Join(", ", Environment!)}";
        }
        if (FilterHelper.IsActive(Environment))
        {
            return $" in environment {String.Join(", ", Environment!)}";
        }
        if (FilterHelper.IsActive(Folder))
        {
            return $" in folder {String.Join(", ", Folder!)}";
        }
        return String.Empty;
    }

    private Server ResolveServer(DbaInstanceParameter instance)
    {
        // The SSIS catalog schema arrived in SQL 2012, so an older instance is refused with the
        // version message rather than failing later on a missing catalog schema.
        Server server = ConnectInstance(instance, "Failure", minimumVersion: 11);
        if (server == null)
        {
            return null!;
        }

        try
        {
            // ConnectionService hands back a Server whose ConnectionContext may still be lazy;
            // SqlConnectionObject is only usable once it has actually connected.
            if (!server.ConnectionContext.IsOpen)
            {
                server.ConnectionContext.Connect();
            }

            if (!CatalogExists(server))
            {
                StopFunction($"No SSIS catalog (SSISDB) found on {instance}", target: instance, continueLoop: true);
                return null!;
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure reaching the SSIS catalog on {instance}", target: instance, exception: ex, continueLoop: true);
            return null!;
        }

        return server;
    }

    private static string? PropertyText(PSObject source, string propertyName)
    {
        PSPropertyInfo? property = source.Properties[propertyName];
        object? value = property?.Value;
        return value == null ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }
}
