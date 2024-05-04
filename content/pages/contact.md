+++
title = "Contact"
description = "To reach us please use the contact form on this page."
path = "contact"
template = "pages.html"
draft = false
+++

## Contact

<p>当サイトへご訪問いただきありがとうございます！ご質問やご意見など、お気軽にお問い合わせください！</p>

<form name="contact" method="POST" id="contact-form">
  <p>
    <label for="name">Name</label>
    <input type="text" placeholder="Name" id="name" required data-validation-required-message="Please enter your name." name="user_name"/>
  </p>
  <p>
    <label for="email">Email Address</label>
    <input type="email" placeholder="name@example.com" id="email" required data-validation-required-message="Please enter your email address." name="user_email"/>
  </p>
  <p>
    <label for="message">Message</label>
    <textarea rows="5" placeholder="Message" id="message" required data-validation-required-message="Please enter a message." name="message"></textarea>
  </p>
  <div id="success"></div>
  <p>
    <button type="submit" id="sendMessageButton">Send</button>
  </p>
</form>


<script type="text/javascript" src="https://cdn.jsdelivr.net/npm/@emailjs/browser@4/dist/email.min.js"></script>
<script type="text/javascript">
    (function() {
        // https://dashboard.emailjs.com/admin/account
        emailjs.init({
          publicKey: "vge4NhvYSMOzIyGlT",
        });
    })();
</script>
<script type="text/javascript">
    document.getElementById('contact-form').addEventListener('submit', function(event) {
        event.preventDefault();
        // these IDs from the previous steps
        emailjs.sendForm('service_losstgc', 'contact_form', this)
            .then(() => {
                console.log('SUCCESS!');
            }, (error) => {
                console.log('FAILED...', error);
            });
    });
</script>

