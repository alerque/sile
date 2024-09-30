#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! mlua = { version = "0.9", features = [ "luajit" ] }
//! ```

fn main() {
    let test = mlua::Lua::new();
    test.load(
        r#"
        print("LUA_PATH:", os.getenv("LUA_PATH"));
        print("HOME:", os.getenv("HOME"))
        print("FOO:", os.getenv("FOO"))
    "#,
    )
    .exec()
    .unwrap();
}
