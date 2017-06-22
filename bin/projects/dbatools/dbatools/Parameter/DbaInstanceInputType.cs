namespace Sqlcollaborative.Dbatools
{
    namespace Parameter
    {
        #region Auxilliary Tools
        /// <summary>
        /// What kind of object was bound to the parameter class?
        /// </summary>
        public enum DbaInstanceInputType
        {
            /// <summary>
            /// Anything, really. An unspecific not reusable type was bound
            /// </summary>
            Default,

            /// <summary>
            /// A live smo linked server object was bound
            /// </summary>
            Linked,

            /// <summary>
            /// A live smo server object was bound
            /// </summary>
            Server,
        }
        #endregion ParameterClass Interna
    }
}