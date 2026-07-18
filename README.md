# zonsite

This project takes a .zon file at compile time and renders a page displaying its contents. Look at [site.zon](site.zon) and [tila.cat](https://tila.cat) to see it in action.

`site.zon` is embedded at compile time and tokenized using `std.zig.Tokenizer`. Each token is wrapped in a colored `<span>`. String literals that look like URLs or email addresses become clickable links.

If you want to use this you need to edit `site.zon`, the `html_head` in `src/main.zig`, and optionally `src/style.css` to change colors.

## Building

Uses Zig 0.16.

Running `zig build` generates the site in `zig-out/`.

## License

[MIT](LICENSE)
