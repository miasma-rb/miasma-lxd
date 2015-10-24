# v0.1.12
* Remove request retry suppression

# v0.1.10
* Make create -> start transition more stable

# v0.1.8
* Proper set server id prior to reload on start

# v0.1.6
* Wait for instance to become available on create
* Retry start when instance still stopped on save

# v0.1.4
* Disable automatic body extraction on remote file fetch

# v0.1.2
* Allow timeout configuration on exec waiter
* Do not automatically close connection on EOF
* Stream uploads instead of full read then write
* Allow return of status code
* Support sending custom environment variables

# v0.1.0
* Initial release
