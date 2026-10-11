#![allow(dead_code)]

include!("main.rs");

use std::{ffi::{CStr, CString, OsString, c_char}, panic::{AssertUnwindSafe, catch_unwind}};

fn c_argument(pointer: *const c_char) -> io::Result<Option<OsString>> {
    if pointer.is_null() { return Ok(None); }
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "Path is not valid UTF-8."))?;
    Ok(Some(OsString::from(value)))
}

fn owned_c_string(value: String) -> *mut c_char {
    CString::new(value).unwrap_or_else(|_| CString::new("Maja could not encode the result.").unwrap()).into_raw()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn maja_list_json(path: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> io::Result<String> {
        let path = c_argument(path)?.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing folder path."))?;
        let path = Path::new(&path);
        listing_json(path)
    }));
    let response = match result {
        Ok(Ok(json)) => json,
        Ok(Err(error)) => format!("{{\"path\":\"\",\"entries\":[],\"error\":{}}}", json_string(&error.to_string())),
        Err(_) => "{\"path\":\"\",\"entries\":[],\"error\":\"The Rust file core encountered an internal error.\"}".to_owned(),
    };
    owned_c_string(response)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn maja_search_json(path: *const c_char, query: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> io::Result<String> {
        let path = c_argument(path)?.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing folder path."))?;
        let query = c_argument(query)?.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing search query."))?;
        let query = query.to_str().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Search query is not valid UTF-8."))?;
        search_json(Path::new(&path), query)
    }));
    let response = match result {
        Ok(Ok(json)) => json,
        Ok(Err(error)) => format!("{{\"path\":\"\",\"entries\":[],\"error\":{}}}", json_string(&error.to_string())),
        Err(_) => "{\"path\":\"\",\"entries\":[],\"error\":\"The Rust file core encountered an internal error.\"}".to_owned(),
    };
    owned_c_string(response)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn maja_run_operation(
    command: *const c_char,
    argument1: *const c_char,
    argument2: *const c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> io::Result<()> {
        let mut arguments = vec![c_argument(command)?.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Missing operation."))?];
        if let Some(value) = c_argument(argument1)? { arguments.push(value); }
        if let Some(value) = c_argument(argument2)? { arguments.push(value); }
        operate(arguments.into_iter())
    }));
    match result {
        Ok(Ok(())) => std::ptr::null_mut(),
        Ok(Err(error)) => owned_c_string(error.to_string()),
        Err(_) => owned_c_string("The Rust file core encountered an internal error.".to_owned()),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn maja_string_free(value: *mut c_char) {
    if !value.is_null() { drop(unsafe { CString::from_raw(value) }); }
}
