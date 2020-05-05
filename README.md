# disposable-imap

<img src="https://github.com/schopenhauer/disposable-imap/blob/master/public/email.png" align="right" width="40" />This Sinatra app allows you to browse emails in a single mailbox  configured as catch-all address on an [IMAP](http://ruby-doc.org/stdlib-2.7.0/libdoc/net/imap/rdoc/Net/IMAP.html) server. This will give you disposable email addresses, as the email traffic is diverted to a single mailbox on your domain.

## Usage

First, you set up a catch-all mailbox on an IMAP server (e.g. Dovecot, Courier) running on `localhost` on port `993`, unless configured differently as shown in the next step.

Second, you may define the following environment variables (alternatively using a `.env` file) on your system:

- `MAIL_DOMAIN` (default value: `example.com`)
- `MAIL_SERVER` (default value: `localhost`)
- `MAIL_PORT` (default value: `993`)
- `MAIL_USERNAME`
- `MAIL_PASSWORD`
- `LOG_SIZE` (optional, default value: 15)
- `INBOX_SIZE` (optional, default value: 15)

Finally, install the gems and run the Sinatra app.

```
bundle install
foreman start
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/schopenhauer/disposable-imap.

## License

The app is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
