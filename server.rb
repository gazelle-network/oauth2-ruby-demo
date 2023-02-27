require "sinatra"
require "faraday"
require "oauth2"

# Normally you'd want to save your users' access tokens somewhere permanent so that they can be retrieved
# and used as needed.  For simplicity of this demo we're just sticking them into a singleton that will go
# away when you restart the server.
set :access_token, {}

# Set these 2 environment variables to the values of your application that you created at
# https://gazelleapp.io/developer/oauth/applications
set :gazelle_app_client_id, ENV["GAZELLE_APP_ID"]
set :gazelle_app_secret, ENV["GAZELLE_APP_SECRET"]

# This is the URL that you want Gazelle to redirect users back to once they have authorized your app.
# You must have added this URL as an "Authorized Callback" in your Gazelle App.
set :gazelle_app_callback_url, ENV["GAZELLE_APP_CALLBACK_URL"]

def oauth2_client
  # Create an OAuth2::Client instance, pointing it to urls for requesting authorization from the
  # user and then for retrieving an access token once authorization is granted.
  OAuth2::Client.new(
    settings.gazelle_app_client_id,  # defined in the settings above, pulled from environment variables
    settings.gazelle_app_secret,     # defined in the settings above, pulled from environment variables
    {
      site: "https://gazelleapp.io",
      authorize_url: "developer/oauth/authorize",
      token_url: "developer/oauth/token"
    }
  )
end

# @param access_token OAuth2::AccessToken
def retrieve_five_pianos(access_token)
  # A GraphQL query string describing the data we wish to fetch.  See https://gazelleapp.io/docs/graphql/private/
  graphql_query_str = <<~QUERY_STR
    query($sortBy: [PianoSort!], $first: Int) {
      allPianos(sortBy: $sortBy, first: $first) {
        nodes { id make model serialNumber }
      }
    }
  QUERY_STR
  # Build a Hash that we'll convert to JSON when we POST the request to Gazelle.
  graphql_query = {
    query: graphql_query_str,
    variables: {
      first: 5,
      sortBy: ["CREATED_AT_DESC"]
    }
  }

  # Do a POST to the Gazelle API endpoint passing in the GraphQL query and variables, passing the
  # access token in the Authorization header.  See documentation here:
  # https://gazelleapp.io/docs/graphql/private/authentication
  response = Faraday.post(
    "https://gazelleapp.io/graphql/private",
    graphql_query.to_json,
    {
      "Content-Type": "application/json",
      "Authorization": "Bearer #{access_token.token}"
    }
  )

  # Parse the return body JSON string and return it.
  JSON.parse(response.body)
end

get '/' do
  # If we haven't authorized and authenticated yet, show a simple page with a button to redirect the
  # user to authorize our app.  Typically you'd be checking for an existing access token from some sort
  # of persistent storage, but in this demo we're simply using an in-memory Ruby Hash stored in
  # settings.access_token.
  if settings.access_token.empty?

    # Use the OAuth2 gem to simplify the process of getting an access token.  Call the oauth2_client
    # method defined up above to create an instance of an OAuth2::Client.
    client = oauth2_client

    # Optional.  You can include a state parameter to help prevent CSRF attacks.  This state parameter
    # can be anything you'd like, but it's typically a random string.  Since it is a string, you can actually
    # pass JSON and a small unique identifier for the user in your system if you'd like.
    # Here's an example of how you might do that:
    state = {
      user_id: 123,
      csrf_token: SecureRandom.hex(16)
    }.to_json

    # If you're passing state along, typically here you would save the CSRF somewhere that can be retrieved
    # later when the user is redirected back to your app.  For this demo we're just going to pass it along
    # and not verify it, but you should definitely do this in a real app.

    # Use the Client object to generate an authorization URL for your Gazelle App id, secret, and callback url.
    # Passing state is optional as noted above.
    @authorize_url = client.auth_code.authorize_url(redirect_uri: settings.gazelle_app_callback_url, state: state)

    # Render the not_authenticated_yet template and return it.
    erb :not_authenticated_yet

  else
    # The user has authorized our app

    # Create an instance of the OAuth2::Client again.
    client = oauth2_client

    # Retrieve the access token from storage.  Typically you'd be retrieving this from a more persistent
    # storage system than we're using in this demo.
    access_token = OAuth2::AccessToken.from_hash(client, settings.access_token[:token_hash])

    # Retrieve 5 pianos
    @five_pianos = retrieve_five_pianos(access_token)

    # Render the five_pianos template and return it.
    erb :five_pianos
  end
end

get '/callback' do
  # Call the oauth2_client method defined up above to create an instance of an OAuth2::Client.
  client = oauth2_client

  # Use the temporary grant code in the request's query parameter to retrieve an access token.
  access_token = client.auth_code.get_token(params["code"], redirect_uri: settings.gazelle_app_callback_url)

  # Optional:  If you passed state in the query parameter of the authorize URL, it will be passed back to you
  # in the state query parameter of the callback URL.  You can use this to verify that the user is who they
  # say they are by verifying the CSRF token you included, and pull off an identifier for the user in your
  # system if you included one.
  if params["state"]
    state = JSON.parse(params["state"])

    my_user_id = state["user_id"]
    my_csrf_token = state["csrf_token"]
    # ... do something with these values ...
  end

  # Now hang on to the access token so that we can use it on subsequent requests to make API calls.
  # Typically you'd hang on to the access token in some more persistent storage system, but for this
  # demo we're simply storing it in an in-memory Hash called settings.access_token.
  settings.access_token[:token_hash] = access_token.to_hash

  # Now redirect back to the main page.
  redirect "/"
end
