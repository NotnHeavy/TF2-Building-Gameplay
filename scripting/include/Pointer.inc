// i don't wanna introduce dependence on smtc so here is this
#if defined notnheavy_building_gameplay_pointer__
#endinput
#endif
#define notnheavy_building_gameplay_pointer__

#define SIZEOF_Pointer 4
#define NULL (view_as<any>(0))

#define SIZEOF(%1) SIZEOF_%1
#define STACK_ALLOC(%1,%2,%3) char SMTC_%1[SIZEOF_%2]; %2 %1 = %2(AddressOfString(SMTC_%1)) // %1 = name, %2 = methodmap, %3 = size to allocate

#define ARRAY Pointer
#define STACK char[]
#define STACK_RETURNREF(%1) return SMTC_%1 // Return a variable allocated with STACK_ALLOC. %1 = variable
#define STACK_RETURNVALUE(%1, %2) char SMTC_%1[%2]; memcpy(AddressOfString(SMTC_%1), %1, %2); return SMTC_%1 // Return a stack-allocated object not used with STACK_ALLOC. %1 = variable, %2 = size to allocate
#define STACK_GETRETURN(%1) AddressOfString(%1) // %1 = variable
#define STACK_SIZEOF(%1) sizeof(SMTC_%1) // %1 = variable

#include <smmem>

#define SMTC_UPDATEMEMACCESS_WHILEWRITING_BYDEFAULT false

methodmap Pointer
{
    // The value this pointer is holding.
    property any Address
    {
        public get() { return view_as<any>(this); }
    }

    // Constructor - wrap around an existing address.
    public Pointer(Address address)
    {
        return view_as<Pointer>(address);
    }

    // Locate the value that this pointer is pointing to and return it, with a given offset.
    public any Dereference(any offset = 0, NumberType bits = NumberType_Int32)
    {
        return LoadFromAddress(this.Address + offset, bits);
    }

    // Write to the address this pointer is holding, with a given offset.
    public void Write(any value, any offset = 0, NumberType bits = NumberType_Int32, bool updateMemAccess = SMTC_UPDATEMEMACCESS_WHILEWRITING_BYDEFAULT)
    {
        StoreToAddress(this.Address + offset, value, bits, updateMemAccess);
    }

    // Get the array offset from the pointer's current address. 
    // You must specify the size of the type used with this pointer using the typeSize parameter.
    public Pointer Get(int index, int typeSize = 4)
    {
        return Pointer(this.Address + view_as<Address>(index * typeSize));
    }
}


// Swap fast between two blocks of memory. You must specify the size of the type used with this global using the typeSize parameter.
stock void V_swap(Pointer x, Pointer y, int typeSize = 4)
{
    Pointer temp = malloc(typeSize);
    memcpy(temp, x, typeSize);
    memcpy(x, y, typeSize);
    memcpy(y, temp, typeSize);
    free(temp);
}

// Re-allocate within a specific location in memory. You must specify the size of the type used with this global using the typeSize parameter.
// Normally this would call the the constructor of the allocated memory, but that's not possible here.
stock void Construct(Pointer memory, int typeSize = 4)
{
    memset(memory, 0, typeSize);
}

// Re-allocate within a specific location in memory, from another source. You must specify the size of the type used with this global using the typeSize parameter.
// Normally this would call the the constructor of the allocated memory, but that's not possible here.
stock void CopyConstruct(Pointer memory, Pointer source, int typeSize = 4)
{
    memcpy(memory, source, typeSize);
}

// Re-allocates a block of memory for an array of num elements. Each byte is initialized as 0.
stock any recalloc(Pointer memory, int num, int size, int old)
{
    Pointer buffer = calloc(num, size);
    memcpy(buffer, memory, old * size);
    free(memory);
    return buffer;
}