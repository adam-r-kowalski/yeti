# Yeti Programming Language

![Yeti Logo](logo.webp)

## Why Yeti

## Syntax Tour

### Primitive Types

i8, i32, i64
Signed integers for whole numbers that might be negative:

i8: For small range integers.

```yeti
temp_change_last_hour: i8 = -2
```

i32: For larger integer values.

```yeti
annual_rainfall_mm: i32 = 1200
```

i64: For very large integers, like cumulative data.

```yeti
total_rainfall_since_setup_mm: i64 = 500000
```

u8, u32, u64
Unsigned integers for non-negative whole numbers:

u8: For small, positive ranges.

```yeti
humidity_percent: u8 = 85
```

u32: For larger positive integers, such as unique IDs.

```yeti
station_id: u32 = 12345
```

u64: For extremely large counts.

```yeti
total_wind_gusts_recorded: u64 = 1500000
```

f32, f64
Floating-point numbers for representing real numbers:

f32: When moderate precision is acceptable.

```yeti
avg_temp_celsius: f32 = 16.5
```

f64: For high-precision measurements.

```yeti
precise_atm_pressure_hpa: f64 = 1013.25
```

bool
For binary conditions:

```yeti
is_raining: bool = true
```

u8
In addition to representing small, positive ranges, u8 can also be used to represent characters. This is particularly useful for compact encoding of data where each byte can represent a single ASCII character.

For instance, in a network of weather stations, each station might be assigned a unique code consisting of a single character to represent different zones or types of data collection points.

```yeti
zone_identifier: u8 = 'A'
```

### Arrays in Yeti

Arrays allow for the storage of multiple items of the same type in an ordered manner. This makes them ideal for situations where you need to keep a collection of similar items together.

#### i64 Array
For a start, an array of `i64` can be used to store historical data that requires large integer values. In the context of our weather station example, we might want to store a series of daily rainfall measurements over a week.

```yeti
weekly_rainfall_mm: []i64 = [10, 20, 5, 0, 30, 60, 25]
```

#### f32 Array
An array of `f32` could be useful for storing a sequence of temperature readings taken at different times of the day, where extreme precision is not critical, but space efficiency is valued.

```yeti
daily_temperatures_celsius: []f32 = [16.5, 18.2, 21.0, 19.5, 17.3]
```

#### u8 Array
Arrays of `u8` can be very useful for storing sequences of characters or bytes. For instance, in a system where each weather station sends a sequence of status codes representing daily operational states, `u8` arrays can be an efficient choice.

```yeti
# 'R' for Running, 'O' for Offline, 'M' for Maintenance
daily_status_codes: []u8 = ['R', 'O', 'O', 'R', 'M']
```

#### bool Array
An array of boolean values (`bool`) is perfect for tracking a series of true/false conditions, such as a week of rain indicators, where each element represents whether it rained on that day.

```yeti
rainy_days: []bool = [true, false, true, false, true, true, false]
```

In the Yeti Programming Language, strings are conceptualized as arrays of `u8` types, where each `u8` element corresponds to a character in the string, based on its ASCII value. This representation aligns with many lower-level programming languages, where strings are essentially sequences of bytes.

### Strings as []u8

The convenience of representing strings as `[]u8` lies in the seamless handling of string data as byte arrays, allowing for efficient storage and manipulation, especially in systems-level programming where control over individual bytes can be crucial.

When you write a string like "hello world" in Yeti, it's understood as an array of `u8` under the hood, each element representing a character's ASCII value:

```yeti
greeting: []u8 = "hello world"
```

#### Real-World Use Case: Weather Station Messages

Consider a weather station that issues daily reports summarizing the weather conditions. These reports can be stored as strings, which, in Yeti, are arrays of `u8`. This approach allows for efficient manipulation of report data at the byte level, which can be particularly useful for encoding, transmitting, or storing these reports in constrained environments.

```yeti
daily_report: []u8 = "Sunny with a slight chance of rain in the afternoon"
```

In this example, the `daily_report` variable holds a human-readable string, but from a technical standpoint, it's managed as an array of bytes (`[]u8`). This dual nature facilitates a range of operations, from simple text manipulation to more complex processing like compression or encryption, all while maintaining a familiar, user-friendly notation for strings.

### Statically Sized Arrays

Statically sized arrays, denoted `[3]i64` for example, have a fixed size determined at compile time. Their fixed length makes them efficient and predictable in terms of memory use, which is particularly advantageous in environments where resources are limited or when performance is critical.

#### Use Case: Fixed Sensor Readings

Imagine a weather station that has exactly three temperature sensors placed at different locations. The readings from these sensors are collected at the same time and need to be processed together.

```yeti
 # Temperature readings from three fixed sensors
sensor_readings: [3]i64 = [12, 14, 13]
```

Here, `sensor_readings` is an array of exactly three `i64` integers, each representing the temperature reading from one of the sensors. The use of a statically sized array ensures that the data structure is compact and that the number of readings is consistent.

### Dynamically Sized Arrays

Dynamically sized arrays, denoted `[]i64`, do not have a fixed size and can grow or shrink at runtime. This flexibility makes them suitable for situations where the amount of data is not known in advance or can vary significantly.

#### Use Case: Variable Weather Event Records

Consider a scenario where a weather station needs to record the occurrence of certain weather events, such as rainfall, over a period of time. Since the number of events can vary, a dynamically sized array is appropriate.

```yeti
 # Rainfall in mm for each event, number of events varies
rainfall_events: []i64 = [10, 15, 20, 5]
```

In this example, `rainfall_events` can hold any number of `i64` values, each representing the amount of rainfall during a particular event. The flexibility of a dynamically sized array accommodates any number of rainfall events that might be recorded.

### Preference for Statically Sized Arrays

While dynamically sized arrays offer more flexibility, statically sized arrays are preferred when the size of the data set is known in advance and is unlikely to change. This preference is due to the efficiency and predictability of statically sized arrays in terms of memory allocation and performance.

In summary, the choice between statically and dynamically sized arrays in Yeti should be informed by the specific requirements of the use case, considering factors such as the known or expected variability in data size and the performance considerations of the application.

The concept of optional types, such as `?i64` in the Yeti Programming Language, is a powerful feature for representing values that may or may not exist. An optional type can either hold a value of its specified type or `null`, indicating the absence of a value. This is particularly useful in scenarios where a value is expected but not guaranteed.

### Use Case: Optional Sensor Data

Consider a weather station equipped with an additional sensor that measures soil moisture levels. However, this sensor might sometimes fail to provide readings due to various reasons like maintenance or malfunctions.

#### Declaring an Optional with a Value

When the sensor provides a valid reading, we can store this value in an optional:

```yeti
# A valid soil moisture reading
soil_moisture_percent: ?i64 = 45
```

Here, `soil_moisture_percent` is an optional `i64` that holds a valid integer value representing the soil moisture level as a percentage.

#### Declaring an Optional with Null

If the sensor fails to provide a reading, we can assign `null` to represent the absence of data:

```yeti
# Sensor reading unavailable
soil_moisture_percent: ?i64 = null
```

In this case, `soil_moisture_percent` is still of type `?i64`, but it holds `null`, indicating that no valid reading is available.

### Why Optionals are Important

Optionals are crucial for robust error handling and data integrity in programming. They explicitly represent the presence or absence of a value, avoiding the misuse of special values (like `-1` or `0`) to indicate "no data," which can lead to ambiguous interpretations. By using optionals, programmers can write more predictable and error-resistant code, as they are forced to explicitly handle the case where a value may not be present. This is particularly useful in data collection, API responses, and any scenario where data might be incomplete or unavailable.

## Functions in Yeti

Functions are essential constructs in Yeti, allowing developers to encapsulate operations in reusable blocks. They enhance code readability, facilitate maintenance, and promote code reuse.

### Why Functions Are Useful

- **Modularity**: Breaking down complex logic into smaller, manageable functions simplifies understanding and debugging.
- **Reusability**: Defined once, functions can be invoked multiple times across different parts of a program.
- **Abstraction**: Functions abstract implementation details, exposing only necessary interfaces to users.

### Function Syntax

Yeti adopts a concise syntax for functions, emphasizing clarity and expressiveness, suitable for both experienced programmers and newcomers.

#### Defining a Function

In Yeti, functions are defined by specifying their parameters, return type, and body. The syntax `{ parameters in body }` is used for brevity and clarity.

```yeti
add: (i32, i32) -> i32 = { x, y in
  x + y
}
```

This function, `add`, takes two `i32` arguments and returns their sum. The `{ x, y in x + y }` syntax succinctly expresses the function's logic.

#### Invoking a Function

Function calls in Yeti are straightforward, employing a clean, whitespace-separated style.

```yeti
result = add 5 10  # Invokes 'add' with 5 and 10 as arguments
```

In this example, `add` is called with `5` and `10`, and the sum, `15`, is assigned to `result`.

#### Higher-Order Functions

Functions in Yeti can be passed as arguments, returned from other functions, and assigned to variables, demonstrating their first-class status.

```yeti
double: (i32) -> i32 = { x in x * 2 }

apply_function: ((i32) -> i32, i32) -> i32 = { f, x in f x }

result = apply_function double 6  # Applies 'double' to 6, resulting in 12
```

`double` is a function that doubles its input. `apply_function` takes a function `f` and an integer `x`, then applies `f` to `x`. Here, `double` is passed to `apply_function` along with `6`, yielding `12`.

### Function Types and Inference

Yeti supports type inference, allowing for more concise function definitions when types are apparent from the context.

```yeti
increment = { x in x + 1 }
```

This `increment` function adds `1` to its input. The types are inferred, simplifying the definition.

### Conclusion

Functions are a cornerstone of Yeti, offering a robust mechanism for structuring code. The language's syntax, favoring both explicit declarations and inference, provides flexibility and caters to diverse programming needs.

## Pointers in Yeti

Pointers are a core feature in Yeti, enabling direct access to the memory locations of variables. This capability is crucial for efficient data manipulation, particularly when mutating data or working with large structures that are impractical to pass around by value.

### Why Pointers Are Useful

- **Direct Memory Access**: Pointers allow for efficient manipulation of data by providing direct access to its memory location.
- **Mutability**: Through pointers, functions can modify the value of variables passed to them, allowing for changes that are reflected across the program.
- **Performance**: Using pointers can significantly reduce memory usage and increase performance, especially with large data structures, by avoiding unnecessary copying of data.

### Pointer Syntax

Yeti's pointer syntax is designed to be intuitive, leveraging familiar concepts while maintaining simplicity and expressiveness.

#### Declaring Pointers

A pointer is declared by prefixing a type with `*`, indicating it stores a memory address of a value of that type.

```yeti
number: mut i32 = 42
number_ptr: *mut i32 = &number  # Creates a pointer to 'number'
```

Here, `number_ptr` is a pointer to an `i32`, specifically holding the address of `number`.

#### Dereferencing Pointers

The `*` operator is used to dereference a pointer, allowing access to or modification of the value at the memory address it points to.

```yeti
*number_ptr += 1  # Increments the value of 'number' through the pointer
```

### Mutating Data with Pointers

Pointers are particularly useful for functions that need to mutate their input parameters, as demonstrated in the `increment` function.

#### Example: Increment Function

This function increments the value of an integer that a pointer points to:

```yeti
increment: (*mut i32) -> () = { number_ptr in
  *number_ptr += 1
}
```

#### Observing Mutation Effects

To see the effect of mutation via pointers, we can assert the value before and after the `increment` function call:

```yeti
original_value: mut i32 = 42
ptr_to_value: *mut i32 = &original_value

# Ensure the initial value is as expected
assert *ptr_to_value == 42

# Increment the value through the pointer
increment ptr_to_value

# Verify the value has been incremented
assert *ptr_to_value == 43
```

In this scenario, `increment ptr_to_value` mutates the value of `original_value` by directly accessing it through the pointer. The `assert` statements confirm the mutation's effectiveness, illustrating how pointers enable direct and impactful modifications to data.

### Conclusion

Pointers in Yeti provide a potent mechanism for directly interacting with memory, offering both efficiency and flexibility. By understanding and utilizing pointers, developers can write more performant Yeti programs that effectively manage and manipulate data.

