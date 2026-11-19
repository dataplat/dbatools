namespace Dataplat.Dbatools.Message
{
    /// <summary>A mutable filter and typed operation for native message processing.</summary>
    public sealed class NativeTransformCondition
    {
        /// <summary>Wildcard filter for the transformed object's type name.</summary>
        public string TypeName;
        /// <summary>Wildcard filter for the originating module.</summary>
        public string ModuleName;
        /// <summary>Wildcard filter for the originating function.</summary>
        public string FunctionName;
        /// <summary>The native operation to apply.</summary>
        public NativeMessageTransform Transform;
        /// <summary>Whether this registration transforms a target or exception.</summary>
        public TransformType Type;

        /// <summary>Creates a condition retaining the supplied descriptor.</summary>
        public NativeTransformCondition(string typeName, string moduleName, string functionName,
            NativeMessageTransform transform, TransformType type)
        {
            TypeName = typeName;
            ModuleName = moduleName;
            FunctionName = functionName;
            Transform = transform;
            Type = type;
        }

        internal bool HasSameFilters(NativeTransformCondition other)
        {
            return TypeName == other.TypeName && ModuleName == other.ModuleName &&
                FunctionName == other.FunctionName && Type == other.Type;
        }

        internal bool Matches(string typeName, string moduleName, string functionName)
        {
            return Utility.UtilityHost.IsLike(typeName, TypeName) &&
                Utility.UtilityHost.IsLike(moduleName, ModuleName) &&
                Utility.UtilityHost.IsLike(functionName, FunctionName);
        }
    }
}
