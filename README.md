# disposable-imap

<img src="https://github.com/schopenhauer/disposable-imap/blob/master/public/email.png" align="right" width="40" />This app allows you to browse an email mailbox configured with a _catch-all_ email address on an [IMAP](https://en.wikipedia.org/wiki/Internet_Message_Access_Protocol) server. This will give you an unlimited number of disposable email addresses.

## Usage

First, you have to set up a _catch-all_ mailbox on an IMAP server (such as [dovecot](https://www.dovecot.org/) or [courier](http://www.courier-mta.org/)) and make sure to have sufficient disk space and mailbox space available.

Next, you have to define the following environment variables on your system:

- `MAIL_DOMAIN` (default value: `example.com`)
- `MAIL_SERVER` (default value: `localhost`)
- `MAIL_PORT` (default value: `993`)
- `MAIL_USERNAME`
- `MAIL_PASSWORD`

Optional configuration:

- `INBOX_SIZE` (optional, default value: 15)
- `LOG_SIZE` (optional, default value: 15)

Alternatively, you can also use a `.env` file in the application root folder.

Finally, install the necessary Ruby gems and run the app.

```
bundle install
foreman start
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/schopenhauer/disposable-imap.

## License

The app is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
