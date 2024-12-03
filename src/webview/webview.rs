use std::ffi::{CStr, CString};
use std::mem;
use std::os::raw::*;
use std::ptr::null_mut;
use std::rc::Rc;

use crate::webview as bindings;

pub enum Window {}

#[repr(i32)]
#[derive(Debug, Clone, Copy, Default)]
pub enum SizeHint {
    /// Width and height are default size
    #[default]
    NONE = 0,
    /// Width and height are minimum bounds
    MIN = 1,
    /// Width and height are maximum bounds
    MAX = 2,
    /// Window size may not be changed by the user
    FIXED = 3,
}

#[derive(Clone)]
pub struct Webview {
    inner: Rc<bindings::webview_t>,
    url: String,
}

unsafe impl Send for Webview {}
unsafe impl Sync for Webview {}

impl Drop for Webview {
    fn drop(&mut self) {
        if Rc::strong_count(&self.inner) == 0 {
            unsafe {
                bindings::webview_terminate(*self.inner);
                bindings::webview_destroy(*self.inner);
            }
        }
    }
}

impl Webview {
    pub fn create(debug: bool, window: Option<&mut Window>) -> Webview {
        if let Some(w) = window {
            Webview {
                inner: Rc::new(unsafe {
                    bindings::webview_create(debug as c_int, w as *mut Window as *mut _)
                }),
                url: "".to_string(),
            }
        } else {
            Webview {
                inner: Rc::new(unsafe { bindings::webview_create(debug as c_int, null_mut()) }),
                url: "".to_string(),
            }
        }
    }

    pub fn run(&mut self) {
        let c_url = CString::new(self.url.as_bytes()).expect("No null bytes in parameter url");
        unsafe { bindings::webview_navigate(*self.inner, c_url.as_ptr()) }
        unsafe { bindings::webview_run(*self.inner) }
    }

    pub fn terminate(&mut self) {
        unsafe { bindings::webview_terminate(*self.inner) }
    }

    // TODO Window instance
    pub fn set_title(&mut self, title: &str) {
        let c_title = CString::new(title).expect("No null bytes in parameter title");
        unsafe { bindings::webview_set_title(*self.inner, c_title.as_ptr()) }
    }

    pub fn set_size(&mut self, width: u16, height: u16, hints: SizeHint) {
        unsafe { bindings::webview_set_size(*self.inner, width, height, hints as i32) }
    }

    pub fn get_window(&self) -> *mut Window {
        unsafe { bindings::webview_get_window(*self.inner) as *mut Window }
    }

    pub fn set_html(&mut self, html: &str) {
        let html = html.to_string();

        self.dispatch(move |wv| {
            let c_html = CString::new(html).expect("Failed to convert HTML");
            unsafe {
                bindings::webview_set_html(*wv.inner, c_html.as_ptr());
            }
        });
    }

    pub fn navigate(&mut self, url: &str) {
        self.url = url.to_string();
    }

    pub fn init(&mut self, js: &str) {
        let c_js = CString::new(js).expect("No null bytes in parameter js");
        unsafe { bindings::webview_init(*self.inner, c_js.as_ptr()) }
    }

    pub fn eval(&mut self, js: &str) {
        let c_js = CString::new(js).expect("No null bytes in parameter js");
        unsafe { bindings::webview_eval(*self.inner, c_js.as_ptr()) }
    }

    pub fn dispatch<F>(&mut self, f: F)
    where
        F: FnOnce(&mut Webview) + Send + 'static,
    {
        let closure = Box::into_raw(Box::new(f));
        extern "C" fn callback<F>(webview: bindings::webview_t, arg: *mut c_void)
        where
            F: FnOnce(&mut Webview) + Send + 'static,
        {
            let mut webview = Webview {
                inner: Rc::new(webview),
                url: "".to_string(),
            };
            let closure: Box<F> = unsafe { Box::from_raw(arg as *mut F) };
            (*closure)(&mut webview);
        }
        unsafe { bindings::webview_dispatch(*self.inner, Some(callback::<F>), closure as *mut _) }
    }

    pub fn bind<F>(&mut self, name: &str, f: F)
    where
        F: FnMut(&str, &str),
    {
        let c_name = CString::new(name).expect("No null bytes in parameter name");
        let closure = Box::into_raw(Box::new(f));
        extern "C" fn callback<F>(seq: *const c_char, req: *const c_char, arg: *mut c_void)
        where
            F: FnMut(&str, &str),
        {
            let seq = unsafe {
                CStr::from_ptr(seq)
                    .to_str()
                    .expect("No null bytes in parameter seq")
            };
            let req = unsafe {
                CStr::from_ptr(req)
                    .to_str()
                    .expect("No null bytes in parameter req")
            };
            let mut f: Box<F> = unsafe { Box::from_raw(arg as *mut F) };
            (*f)(seq, req);
            mem::forget(f);
        }
        unsafe {
            bindings::webview_bind(
                *self.inner,
                c_name.as_ptr(),
                Some(callback::<F>),
                closure as *mut _,
            )
        }
    }

    pub fn r#return(&self, seq: &str, status: c_int, result: &str) {
        let c_seq = CString::new(seq).expect("No null bytes in parameter seq");
        let c_result = CString::new(result).expect("No null bytes in parameter result");
        unsafe { bindings::webview_return(*self.inner, c_seq.as_ptr(), status, c_result.as_ptr()) }
    }
}
