#!/usr/bin/env python3

import threading

import cv2
import rospy
from cv_bridge import CvBridge
from sensor_msgs.msg import CameraInfo, CompressedImage, Image


class BLTCameraAdapter:

    SOURCE_WIDTH = 1920.0
    TARGET_WIDTH = 704
    TARGET_HEIGHT = 384
    RESIZED_HEIGHT = 396
    CROP_TOP = 6
    SCALE = TARGET_WIDTH / SOURCE_WIDTH

    def __init__(self) -> None:
        self.bridge = CvBridge()
        self.camera_info_lock = threading.Lock()
        self.latest_camera_info = None

        input_image_topic = rospy.get_param(
            "~input_image_topic", "/front/zed_node/rgb/image_rect_color/compressed")
        input_camera_info_topic = rospy.get_param("~input_camera_info_topic",
                                                  "/front/zed_node/rgb/camera_info")
        output_image_topic = rospy.get_param("~output_image_topic", "/camera_undistorted/image")
        output_camera_info_topic = rospy.get_param("~output_camera_info_topic",
                                                   "/camera_undistorted/camera_info")

        self.image_publisher = rospy.Publisher(output_image_topic, Image, queue_size=1)
        self.camera_info_publisher = rospy.Publisher(output_camera_info_topic, CameraInfo, queue_size=1)

        rospy.Subscriber(input_camera_info_topic, CameraInfo, self._camera_info_callback, queue_size=1)
        rospy.Subscriber(input_image_topic,
                         CompressedImage,
                         self._image_callback,
                         queue_size=1,
                         buff_size=2**24)

    def _camera_info_callback(self, msg: CameraInfo) -> None:
        adjusted_msg = self._adjust_camera_info(msg)
        with self.camera_info_lock:
            self.latest_camera_info = adjusted_msg
        self.camera_info_publisher.publish(adjusted_msg)

    def _image_callback(self, msg: CompressedImage) -> None:
        image_bgr = self.bridge.compressed_imgmsg_to_cv2(msg, desired_encoding="bgr8")
        resized_bgr = cv2.resize(image_bgr,
                                 (self.TARGET_WIDTH, self.RESIZED_HEIGHT),
                                 interpolation=cv2.INTER_AREA)
        cropped_bgr = resized_bgr[self.CROP_TOP:self.CROP_TOP + self.TARGET_HEIGHT, :, :]
        cropped_rgb = cv2.cvtColor(cropped_bgr, cv2.COLOR_BGR2RGB)

        image_msg = self.bridge.cv2_to_imgmsg(cropped_rgb, encoding="rgb8")
        image_msg.header = msg.header
        self.image_publisher.publish(image_msg)

        with self.camera_info_lock:
            latest_camera_info = self.latest_camera_info
        if latest_camera_info is not None:
            latest_camera_info.header = msg.header
            self.camera_info_publisher.publish(latest_camera_info)

    def _adjust_camera_info(self, msg: CameraInfo) -> CameraInfo:
        adjusted_msg = CameraInfo()
        adjusted_msg.header = msg.header
        adjusted_msg.height = self.TARGET_HEIGHT
        adjusted_msg.width = self.TARGET_WIDTH
        adjusted_msg.distortion_model = msg.distortion_model
        adjusted_msg.D = [0.0 for _ in msg.D]
        adjusted_msg.binning_x = 0
        adjusted_msg.binning_y = 0
        adjusted_msg.roi = msg.roi
        adjusted_msg.roi.x_offset = 0
        adjusted_msg.roi.y_offset = 0
        adjusted_msg.roi.height = 0
        adjusted_msg.roi.width = 0
        adjusted_msg.roi.do_rectify = False

        adjusted_msg.K = list(msg.K)
        adjusted_msg.K[0] *= self.SCALE
        adjusted_msg.K[2] *= self.SCALE
        adjusted_msg.K[4] *= self.SCALE
        adjusted_msg.K[5] = adjusted_msg.K[5] * self.SCALE - self.CROP_TOP

        adjusted_msg.R = list(msg.R)

        adjusted_msg.P = list(msg.P)
        adjusted_msg.P[0] *= self.SCALE
        adjusted_msg.P[2] *= self.SCALE
        adjusted_msg.P[5] *= self.SCALE
        adjusted_msg.P[6] = adjusted_msg.P[6] * self.SCALE - self.CROP_TOP

        return adjusted_msg


if __name__ == "__main__":
    rospy.init_node("blt_camera_adapter")
    BLTCameraAdapter()
    rospy.spin()
