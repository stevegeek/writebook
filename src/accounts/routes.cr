module Accounts
  ROUTES = Marten::Routing::Map.draw do
    path "/first_run", FirstRunNewHandler, name: "first_run_new"
    path "/first_run/create", FirstRunCreateHandler, name: "first_run_create"

    path "/session/new", SessionsNewHandler, name: "session_new"
    path "/session/create", SessionsCreateHandler, name: "session_create"
    path "/session/destroy", SessionsDeleteHandler, name: "session_destroy"

    path "/users", UsersIndexHandler, name: "users_index"
    path "/users/<id:int>/update", UsersUpdateHandler, name: "users_update"
    path "/users/<id:int>/delete", UsersDeleteHandler, name: "users_delete"
    path "/users/<id:int>/profile", ProfilesShowHandler, name: "profile_show_user"
    path "/users/<id:int>/profile/edit", ProfilesEditHandler, name: "profile_edit_user"
    path "/join/<join_code:str>", UsersNewHandler, name: "users_new"

    path "/profile", ProfilesShowHandler, name: "profile_show"
    path "/profile/edit", ProfilesEditHandler, name: "profile_edit"

    path "/account/custom_styles", CustomStylesEditHandler, name: "custom_styles_edit"
    path "/account/join_codes", JoinCodesCreateHandler, name: "join_codes_create"

    path "/qr/<code:str>", QrCodeHandler, name: "qr_code"

    path "/session/transfer/<token:str>", SessionsTransfersShowHandler, name: "transfers_show"
    path "/session/transfer/<token:str>/redeem", SessionsTransfersRedeemHandler, name: "transfers_redeem"
    path "/session/transfer/<token:str>/qr", SessionsTransfersQrHandler, name: "transfer_qr"
  end
end
