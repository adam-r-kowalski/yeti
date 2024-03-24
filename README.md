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
